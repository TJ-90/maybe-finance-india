require "test_helper"

# End to end checks that the Indian providers plug into MarketDataImporter, the price importers and holdings.
# All HTTP is stubbed with webmock; nothing here reaches the network.
class IndianMarketDataTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    Security::Price.delete_all
    ExchangeRate.delete_all
    Trade.delete_all
    Holding.delete_all
    Security.delete_all
    Entry.delete_all

    @family = Family.create!(name: "Sharma", currency: "INR", country: "IN")
    @account = @family.accounts.create!(name: "Demat", balance: 0, currency: "INR", accountable: Investment.new)
    @trade_date = 8.days.ago.to_date
  end

  test "MF trade gets NAV history from MFAPI and the holding is valued from it" do
    security = Security.create!(ticker: "100001", exchange_operating_mic: "AMFI")
    navs = (@trade_date - 7.days..Date.current).to_h { |date| [ date, 240 + (date - @trade_date).to_i ] }
    stub_request(:get, "https://api.mfapi.in/mf/100001").to_return(status: 200, body: mfapi_body(navs))
    create_trade(security, account: @account, qty: 10, date: @trade_date, price: 240, currency: "INR")

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil do
      assert_instance_of Provider::IndianMarkets, Security.provider
      MarketDataImporter.new(mode: :full).import_security_prices
    end

    prices = security.prices.order(:date)
    assert prices.any?
    assert_equal [ "INR" ], prices.pluck(:currency).uniq
    assert_equal BigDecimal("240"), prices.find_by(date: @trade_date).price

    Holding::Materializer.new(@account, strategy: :forward).materialize_holdings

    holding = @account.holdings.where(security: security).order(:date).last
    assert_equal Date.current, holding.date
    assert_equal 10, holding.qty
    assert_equal BigDecimal("248"), holding.price
    assert_equal BigDecimal("2480"), holding.amount
    assert_equal mutual_fund_schemes(:bluechip_direct).name, holding.name
  end

  test "NSE security gets daily prices from Yahoo" do
    security = Security.create!(ticker: "TESTNSE", exchange_operating_mic: "XNSE", name: "Test NSE Ltd")
    stub_request(:get, %r{query1\.finance\.yahoo\.com/v8/finance/chart/TESTNSE\.NS}).to_return(status: 200, body: yahoo_body(@trade_date - 7.days..Date.current))
    create_trade(security, account: @account, qty: 5, date: @trade_date, price: 100, currency: "INR")

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil do
      MarketDataImporter.new(mode: :full).import_security_prices
    end

    prices = security.prices.order(:date)
    assert prices.where(date: @trade_date).exists?
    assert_equal [ "INR" ], prices.pluck(:currency).uniq
    assert prices.last.price > 0
  end

  test "USD to INR rates are imported from Frankfurter" do
    @family.accounts.create!(name: "US brokerage", balance: 0, currency: "USD", accountable: Investment.new)
    stub_request(:get, %r{api\.frankfurter\.app/\d{4}-\d{2}-\d{2}\.\.\d{4}-\d{2}-\d{2}}).with(query: { from: "USD", to: "INR" }).to_return do |request|
      start_date = Date.iso8601(request.uri.path.delete_prefix("/").split("..").first)
      rates = (start_date..start_date + 12).reject { |d| d.saturday? || d.sunday? }.to_h { |d| [ d.to_s, { INR: 88.0 } ] }
      { status: 200, body: { base: "USD", rates: rates }.to_json }
    end

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil do
      MarketDataImporter.new(mode: :snapshot).import_exchange_rates
    end

    assert ExchangeRate.where(from_currency: "USD", to_currency: "INR").exists?
    assert_equal BigDecimal("88.0"), ExchangeRate.find_by!(from_currency: "USD", to_currency: "INR", date: Date.current).rate
  end

  test "importers do nothing when Indian market data is disabled and no other provider exists" do
    Setting.stubs(:synth_api_key).returns(nil)
    security = Security.create!(ticker: "100001", exchange_operating_mic: "AMFI")

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: "true", SYNTH_API_KEY: nil do
      assert_nil Security.provider
      assert_nil ExchangeRate.provider
      MarketDataImporter.new(mode: :snapshot).import_all
    end

    assert_empty security.prices
    assert_not_requested :any, /.*/
  end

  private
    def mfapi_body(navs)
      {
        meta: { scheme_code: 100001, scheme_name: "Alpha Bluechip Fund - Direct Plan - Growth" },
        data: navs.sort_by { |date, _| date }.reverse.map { |date, nav| { date: date.strftime("%d-%m-%Y"), nav: nav.to_s } },
        status: "SUCCESS"
      }.to_json
    end

    def yahoo_body(dates)
      zone = ActiveSupport::TimeZone["Asia/Kolkata"]
      days = dates.to_a
      {
        chart: {
          result: [ {
            meta: { currency: "INR", symbol: "TESTNSE.NS", instrumentType: "EQUITY", longName: "Test NSE Ltd" },
            timestamp: days.map { |d| zone.local(d.year, d.month, d.day, 9, 15).to_i },
            indicators: { quote: [ { close: days.each_index.map { |i| 100.0 + i } } ] }
          } ],
          error: nil
        }
      }.to_json
    end
end
