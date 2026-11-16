require "test_helper"
require "ostruct"

class RefreshIntradayPricesJobTest < ActiveJob::TestCase
  include TaxTestHelper

  MARKET_HOURS = Time.utc(2026, 11, 16, 5, 0) # Monday 10:30 IST

  setup do
    @family = inr_family
    @account = create_investment_account(@family)
    @held = Security.create!(ticker: "RELIANCE", name: "Reliance", exchange_operating_mic: "XNSE", kind: "stock")
    @not_held = Security.create!(ticker: "TCS", name: "TCS", exchange_operating_mic: "XNSE", kind: "stock")
    @fund = Security.create!(ticker: "900001", name: "A fund", exchange_operating_mic: "AMFI", kind: "mutual_fund")

    create_folio_trade @account, @held, qty: 10, price: 2800, date: 30.days.ago.to_date
    create_folio_trade @account, @fund, qty: 10, price: 60, date: 30.days.ago.to_date
    Sync.delete_all

    @provider = mock("provider")
    @provider.stubs(:respond_to?).returns(true)
    Security.stubs(:provider).returns(@provider)
    Security::IntradayRefresh.any_instance.stubs(:sleep)
  end

  def quote(price, date: Date.new(2026, 11, 16))
    Provider::Response.new(success?: true, error: nil, data: OpenStruct.new(date: date, price: BigDecimal(price.to_s), currency: "INR"))
  end

  def failure
    Provider::Response.new(success?: false, data: nil, error: StandardError.new("429"))
  end

  test "writes today's price for held exchange securities only and re-values their accounts" do
    @provider.expects(:fetch_latest_price).with(symbol: "RELIANCE", exchange_operating_mic: "XNSE").returns(quote(2950)).once

    travel_to(MARKET_HOURS) do
      RefreshIntradayPricesJob.perform_now
    end

    assert_equal BigDecimal("2950"), @held.prices.find_by!(date: Date.new(2026, 11, 16)).price
    assert_equal 0, @not_held.prices.count
    assert_equal 0, @fund.prices.count
    assert_equal 1, @account.syncs.count
    assert_equal Date.new(2026, 11, 16), @account.syncs.first.window_start_date
  end

  test "updates today's price in place and skips the re-valuation when nothing moved" do
    Security::Price.create!(security: @held, date: Date.new(2026, 11, 16), price: 2900, currency: "INR")
    @provider.stubs(:fetch_latest_price).returns(quote(2900))

    travel_to(MARKET_HOURS) { RefreshIntradayPricesJob.perform_now }
    assert_equal 0, @account.syncs.count

    @provider.stubs(:fetch_latest_price).returns(quote(2910))
    travel_to(MARKET_HOURS) { RefreshIntradayPricesJob.perform_now }

    assert_equal 1, @held.prices.count
    assert_equal BigDecimal("2910"), @held.prices.first.price
    assert_equal 1, @account.syncs.count
  end

  test "does nothing outside market hours or at the weekend" do
    @provider.expects(:fetch_latest_price).never

    travel_to(Time.utc(2026, 11, 16, 11, 0)) { RefreshIntradayPricesJob.perform_now } # 16:30 IST
    travel_to(Time.utc(2026, 11, 21, 5, 0)) { RefreshIntradayPricesJob.perform_now } # Saturday

    assert_equal 0, @held.prices.count
  end

  test "does nothing when INTRADAY_PRICE_REFRESH is false" do
    @provider.expects(:fetch_latest_price).never

    with_env_overrides INTRADAY_PRICE_REFRESH: "false" do
      travel_to(MARKET_HOURS) { RefreshIntradayPricesJob.perform_now }
    end

    assert_equal 0, @held.prices.count
  end

  test "backs off when every request in a batch fails" do
    extra = (1..3).map { |i| Security.create!(ticker: "STOCK#{i}", name: "Stock #{i}", exchange_operating_mic: "XNSE", kind: "stock") }
    extra.each { |security| create_folio_trade @account, security, qty: 1, price: 100, date: 30.days.ago.to_date }

    # batches of 2: the first batch fails entirely, so the second is never requested
    @provider.expects(:fetch_latest_price).times(2).returns(failure)

    travel_to(MARKET_HOURS) do
      assert_empty Security::IntradayRefresh.new(provider: @provider, batch_size: 2, pause: 0).refresh
    end
  end

  test "one failing security does not stop the others" do
    other = Security.create!(ticker: "INFY", name: "Infosys", exchange_operating_mic: "XNSE", kind: "stock")
    create_folio_trade @account, other, qty: 1, price: 1500, date: 30.days.ago.to_date

    @provider.stubs(:fetch_latest_price).with(symbol: "RELIANCE", exchange_operating_mic: "XNSE").returns(failure)
    @provider.stubs(:fetch_latest_price).with(symbol: "INFY", exchange_operating_mic: "XNSE").returns(quote(1600))

    changed = Security::IntradayRefresh.new(provider: @provider, pause: 0).refresh

    assert_equal [ other.id ], changed
  end

  test "is scheduled every 15 minutes on weekdays, and the NSE/BSE close import at 16:15 IST" do
    schedule = YAML.load_file(Rails.root.join("config/schedule.yml"))

    assert_equal "RefreshIntradayPricesJob", schedule.dig("refresh_intraday_prices", "class")
    assert_equal "*/15 3-10 * * 1-5", schedule.dig("refresh_intraday_prices", "cron")
    assert_equal "45 10 * * 1-5", schedule.dig("import_exchange_close_prices", "cron")
    assert_equal "exchange_close", schedule.dig("import_exchange_close_prices", "args", "scope")
    assert_equal "ImportMarketDataJob", schedule.dig("import_exchange_close_prices", "class")
  end
end
