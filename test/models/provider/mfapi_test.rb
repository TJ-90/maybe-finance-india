require "test_helper"

class Provider::MfapiTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::Mfapi.new
    @url = "https://api.mfapi.in/mf/100001"
    MutualFundScheme.delete_all
    MutualFundScheme.create!(scheme_code: "100001", name: "Alpha Bluechip Fund - Direct Plan - Growth", amc: "Alpha Sample Mutual Fund", category: "Equity Scheme - Large Cap Fund")
    MutualFundScheme.create!(scheme_code: "100002", name: "Alpha Liquid Fund - Direct Plan - Growth", amc: "Alpha Sample Mutual Fund")
    MutualFundScheme.create!(scheme_code: "100003", name: "Closed Fund", active: false)
  end

  test "searches the local scheme table without any network call" do
    response = @provider.search_securities("bluechip alpha")

    assert response.success?
    assert_equal [ "100001" ], response.data.map(&:symbol)
    assert_equal "AMFI", response.data.first.exchange_operating_mic
    assert_equal "IN", response.data.first.country_code
    assert_equal "mutual_fund", response.data.first.kind
    assert_not_requested :any, /mfapi/
  end

  test "searches by scheme code and skips inactive schemes" do
    assert_equal [ "100002" ], @provider.search_securities("100002").data.map(&:symbol)
    assert_empty @provider.search_securities("Closed Fund").data
  end

  test "search is empty for other exchanges and countries" do
    assert_empty @provider.search_securities("alpha", exchange_operating_mic: "XNAS").data
    assert_empty @provider.search_securities("alpha", country_code: "US").data
  end

  test "fetches historical NAVs in a date range" do
    stub_request(:get, @url).to_return(status: 200, body: file_fixture("mfapi_scheme_100001.json").read)

    response = @provider.fetch_security_prices(symbol: "100001", exchange_operating_mic: "AMFI", start_date: Date.new(2026, 11, 3), end_date: Date.new(2026, 11, 5))

    assert response.success?
    assert_equal [ Date.new(2026, 11, 3), Date.new(2026, 11, 4), Date.new(2026, 11, 5) ], response.data.map(&:date)
    assert_equal BigDecimal("245.1234"), response.data.second.price
    assert_equal "INR", response.data.first.currency
    assert_equal "AMFI", response.data.first.exchange_operating_mic
  end

  test "single price falls back to the latest NAV on or before the date" do
    stub_request(:get, @url).to_return(status: 200, body: file_fixture("mfapi_scheme_100001.json").read)

    response = @provider.fetch_security_price(symbol: "100001", exchange_operating_mic: "AMFI", date: Date.new(2026, 11, 8))

    assert response.success?
    assert_equal Date.new(2026, 11, 6), response.data.date
    assert_equal BigDecimal("246.5"), response.data.price
  end

  test "returns an error response for unknown schemes" do
    stub_request(:get, "https://api.mfapi.in/mf/999").to_return(status: 200, body: { status: "ERROR", message: "Not found" }.to_json)

    response = @provider.fetch_security_prices(symbol: "999", exchange_operating_mic: "AMFI", start_date: Date.new(2026, 11, 1), end_date: Date.new(2026, 11, 5))

    assert_not response.success?
  end

  test "fetch_security_info uses the local scheme name" do
    response = @provider.fetch_security_info(symbol: "100001", exchange_operating_mic: "AMFI")

    assert response.success?
    assert_equal "Alpha Bluechip Fund - Direct Plan - Growth", response.data.name
  end
end
