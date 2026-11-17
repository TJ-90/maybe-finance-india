require "test_helper"

class MutualFundsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "lists active funds with NAVs" do
    get mutual_funds_url

    assert_response :success
    assert_select "a[href=?]", mutual_fund_path(mutual_fund_schemes(:bluechip_direct)), text: /Alpha Bluechip Fund - Direct Plan - Growth/
    assert_match "Gamma Nifty 50 Index Fund", response.body
    assert_match "245.12", response.body
  end

  test "searches by name" do
    get mutual_funds_url, params: { q: { q: "nifty" } }

    assert_response :success
    assert_match "Gamma Nifty 50 Index Fund", response.body
    assert_no_match "Alpha Bluechip", response.body
  end

  test "filters by AMC, category, plan, option and style" do
    get mutual_funds_url, params: { q: { amc: "Alpha Sample Mutual Fund" } }
    assert_match "Alpha Bluechip Fund - Direct", response.body
    assert_no_match "Gamma Nifty", response.body

    get mutual_funds_url, params: { q: { plan: "regular" } }
    assert_match "Regular Plan - IDCW", response.body
    assert_no_match "Direct Plan - Growth", response.body

    get mutual_funds_url, params: { q: { option: "growth", style: "passive" } }
    assert_match "Gamma Nifty 50 Index Fund", response.body
    assert_no_match "Alpha Bluechip", response.body

    get mutual_funds_url, params: { q: { category: "Equity Scheme - Large Cap Fund", style: "active" } }
    assert_match "Alpha Bluechip Fund - Direct", response.body
    assert_no_match "Gamma Nifty", response.body
  end

  test "paginates results" do
    get mutual_funds_url, params: { per_page: 10 }
    assert_response :success

    25.times { |i| MutualFundScheme.create!(scheme_code: "9#{i}", name: "Zeta Fund #{i}", amc: "Zeta", category: "Equity Scheme - Large Cap Fund") }

    get mutual_funds_url, params: { per_page: 10 }
    assert_response :success
    assert_select "nav a[href*='page=2']"

    get mutual_funds_url, params: { per_page: 10, page: 3 }
    assert_response :success
  end

  test "shows an empty state with a hint before the first import" do
    MutualFundScheme.delete_all

    get mutual_funds_url

    assert_response :success
    assert_match "No funds found", response.body
    assert_select "a[href=?]", settings_market_data_path
  end

  test "show page renders NAV history and add-to-account actions" do
    scheme = mutual_fund_schemes(:bluechip_direct)
    provider = mock("provider")
    Security.stubs(:provider).returns(provider)
    prices = (1..5).map do |i|
      Provider::SecurityConcept::Price.new(symbol: scheme.scheme_code, date: Date.current - (6 - i).days, price: 240 + i, currency: "INR", exchange_operating_mic: "AMFI")
    end
    provider.stubs(:fetch_security_prices).returns(Provider::Response.new(success?: true, data: prices, error: nil))
    account = users(:family_admin).family.accounts.create!(name: "My demat", balance: 0, currency: "INR", accountable: Investment.new)

    get mutual_fund_url(scheme)

    assert_response :success
    assert_select "#navHistoryChart[data-controller='time-series-chart']"
    assert_select "a[href=?]", new_trade_path(account_id: account.id, ticker: "100001|AMFI")
    assert_match "INF000A01001", response.body
  end

  test "show page shows trailing 1Y, 3Y and 5Y CAGR from NAV history" do
    scheme = mutual_fund_schemes(:bluechip_direct)
    provider = mock("provider")
    Security.stubs(:provider).returns(provider)
    history = { Date.current => 144, 1.year.ago.to_date => 120, 3.years.ago.to_date => 100 }
    prices = history.map do |date, nav|
      Provider::SecurityConcept::Price.new(symbol: scheme.scheme_code, date: date, price: nav, currency: "INR", exchange_operating_mic: "AMFI")
    end
    provider.expects(:fetch_security_prices).with { |args| args[:start_date] <= 5.years.ago.to_date }.returns(Provider::Response.new(success?: true, data: prices, error: nil))

    get mutual_fund_url(scheme)

    assert_response :success
    assert_select "#trailing-returns dd", text: "20.0%"
    assert_select "#trailing-returns dd", text: "12.9%"
    assert_select "#trailing-returns dd", text: "--"
  end

  test "show page works without NAV history" do
    Security.stubs(:provider).returns(nil)

    get mutual_fund_url(mutual_fund_schemes(:bluechip_direct))

    assert_response :success
    assert_match "NAV history is not available", response.body
  end

  test "trade form is pre-filled with the chosen fund" do
    account = users(:family_admin).family.accounts.create!(name: "My demat", balance: 0, currency: "INR", accountable: Investment.new)

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil do
      get new_trade_url(account_id: account.id, ticker: "100001|AMFI")
    end

    assert_response :success
    assert_select "input[type=hidden][value=?]", "100001|AMFI"
    assert_match "Alpha Bluechip Fund - Direct Plan - Growth (AMFI 100001)", response.body
  end

  test "creating a mutual fund trade stores the folio and resolves the AMFI security" do
    account = users(:family_admin).family.accounts.create!(name: "My demat", balance: 0, currency: "INR", accountable: Investment.new)
    scheme = mutual_fund_schemes(:bluechip_direct)

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil do
      assert_difference [ "Trade.count", "Security.count" ], 1 do
        post trades_url(account_id: account.id), params: {
          model: { type: "buy", date: Date.current, ticker: "100001|AMFI", qty: "10", price: "245.12", currency: "INR", folio_number: "1234567/89" }
        }
      end
    end

    trade = Trade.order(:created_at).last
    assert_equal "1234567/89", trade.folio_number
    assert_equal scheme.scheme_code, trade.security.ticker
    assert_equal "mutual_fund", trade.security.kind
    assert_not trade.security.offline?, "resolved through the AMFI search, not created as an offline ticker"
    assert_equal scheme.name, trade.security.name
    assert_includes trade.entry.name, scheme.name
  end
end
