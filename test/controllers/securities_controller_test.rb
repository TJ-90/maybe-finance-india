require "test_helper"

class SecuritiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "finds mutual funds by name and NSE or BSE symbols, with kind badges" do
    stub_request(:get, %r{query2\.finance\.yahoo\.com/v1/finance/search}).to_return(status: 200, body: file_fixture("yahoo_search_sample.json").read)

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil do
      get securities_url(q: "alpha", format: :turbo_stream)
    end

    assert_response :success
    assert_match "Alpha Bluechip Fund - Direct Plan - Growth", response.body
    assert_match "100001 (AMFI)", response.body
    assert_match ">MF<", response.body.gsub(/\s+/, "")
    assert_match "RELIANCE (XNSE)", response.body
    assert_match ">NSE<", response.body.gsub(/\s+/, "")
    assert_match ">BSE<", response.body.gsub(/\s+/, "")
  end

  test "still returns mutual funds when Yahoo is down" do
    stub_request(:get, %r{query2\.finance\.yahoo\.com/v1/finance/search}).to_return(status: 429)

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil do
      get securities_url(q: "bluechip", format: :turbo_stream)
    end

    assert_response :success
    assert_match "Alpha Bluechip Fund - Direct Plan - Growth", response.body
  end
end
