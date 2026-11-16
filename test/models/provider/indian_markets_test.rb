require "test_helper"

class Provider::IndianMarketsTest < ActiveSupport::TestCase
  include ProviderTestHelper

  setup do
    @mfapi = mock("mfapi")
    @yahoo = mock("yahoo")
    @fallback = mock("fallback")
    @provider = Provider::IndianMarkets.new(mfapi: @mfapi, yahoo: @yahoo, fallback: @fallback)
    @args = { symbol: "X", start_date: Date.new(2026, 11, 1), end_date: Date.new(2026, 11, 5) }
  end

  test "routes AMFI prices to MFAPI" do
    @mfapi.expects(:fetch_security_prices).with(**@args, exchange_operating_mic: "AMFI").returns(provider_success_response([]))
    @yahoo.expects(:fetch_security_prices).never

    assert @provider.fetch_security_prices(**@args, exchange_operating_mic: "AMFI").success?
  end

  test "routes NSE and BSE prices to Yahoo" do
    @yahoo.expects(:fetch_security_prices).with(**@args, exchange_operating_mic: "XNSE").returns(provider_success_response([]))
    @yahoo.expects(:fetch_security_prices).with(**@args, exchange_operating_mic: "XBOM").returns(provider_success_response([]))
    @mfapi.expects(:fetch_security_prices).never

    assert @provider.fetch_security_prices(**@args, exchange_operating_mic: "XNSE").success?
    assert @provider.fetch_security_prices(**@args, exchange_operating_mic: "XBOM").success?
  end

  test "routes other exchanges to the fallback provider" do
    @fallback.expects(:fetch_security_price).with(symbol: "AAPL", exchange_operating_mic: "XNAS", date: Date.new(2026, 11, 1)).returns(provider_success_response(:price))

    assert_equal :price, @provider.fetch_security_price(symbol: "AAPL", exchange_operating_mic: "XNAS", date: Date.new(2026, 11, 1)).data
  end

  test "returns an error response when no provider serves the exchange" do
    provider = Provider::IndianMarkets.new(mfapi: @mfapi, yahoo: @yahoo)

    response = provider.fetch_security_prices(**@args, exchange_operating_mic: "XNAS")

    assert_not response.success?
    assert_match "XNAS", response.error.message
  end

  test "search merges mutual fund and equity results" do
    fund = Provider::SecurityConcept::Security.new(symbol: "100001", name: "Alpha Fund", logo_url: nil, exchange_operating_mic: "AMFI", country_code: "IN")
    stock = Provider::SecurityConcept::Security.new(symbol: "ALPHA", name: "Alpha Ltd", logo_url: nil, exchange_operating_mic: "XNSE", country_code: "IN")
    @mfapi.expects(:search_securities).with("alpha").returns(provider_success_response([ fund ]))
    @yahoo.expects(:search_securities).with("alpha").returns(provider_success_response([ stock ]))
    @fallback.expects(:search_securities).with("alpha").returns(provider_success_response([]))

    response = @provider.search_securities("alpha")

    assert_equal [ "100001", "ALPHA" ], response.data.map(&:symbol)
  end

  test "search keeps local fund results when Yahoo fails" do
    fund = Provider::SecurityConcept::Security.new(symbol: "100001", name: "Alpha Fund", logo_url: nil, exchange_operating_mic: "AMFI", country_code: "IN")
    @mfapi.expects(:search_securities).returns(provider_success_response([ fund ]))
    @yahoo.expects(:search_securities).returns(provider_error_response(Provider::YahooFinance::Error.new("boom")))
    @fallback.expects(:search_securities).returns(provider_success_response([]))

    response = @provider.search_securities("alpha")

    assert response.success?
    assert_equal [ "100001" ], response.data.map(&:symbol)
  end

  test "search with an exchange only asks that exchange's provider" do
    @mfapi.expects(:search_securities).with("119", exchange_operating_mic: "AMFI").returns(provider_success_response([]))
    @yahoo.expects(:search_securities).never

    assert @provider.search_securities("119", exchange_operating_mic: "AMFI").success?
  end

  test "search skips the fallback for Indian families" do
    @mfapi.expects(:search_securities).returns(provider_success_response([]))
    @yahoo.expects(:search_securities).returns(provider_success_response([]))
    @fallback.expects(:search_securities).never

    @provider.search_securities("alpha", country_code: "IN")
  end
end
