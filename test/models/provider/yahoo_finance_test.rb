require "test_helper"

class Provider::YahooFinanceTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::YahooFinance.new
    @chart_url = %r{https://query1\.finance\.yahoo\.com/v8/finance/chart/RELIANCE\.NS}
  end

  test "fetches daily closes for an NSE symbol, skipping null closes" do
    stub_request(:get, @chart_url).to_return(status: 200, body: file_fixture("yahoo_chart_reliance.json").read)

    response = @provider.fetch_security_prices(symbol: "RELIANCE", exchange_operating_mic: "XNSE", start_date: Date.new(2026, 11, 2), end_date: Date.new(2026, 11, 5))

    assert response.success?
    assert_equal [ Date.new(2026, 11, 2), Date.new(2026, 11, 4), Date.new(2026, 11, 5) ], response.data.map(&:date)
    assert_equal BigDecimal("2900.5"), response.data.first.price
    assert_equal "INR", response.data.first.currency
    assert_equal "XNSE", response.data.first.exchange_operating_mic
  end

  test "maps BSE to the .BO suffix and sends a browser user agent" do
    stub = stub_request(:get, %r{/v8/finance/chart/500325\.BO}).with(headers: { "User-Agent" => /Mozilla/ })
      .to_return(status: 200, body: file_fixture("yahoo_chart_reliance.json").read)

    response = @provider.fetch_security_prices(symbol: "500325", exchange_operating_mic: "XBOM", start_date: Date.new(2026, 11, 2), end_date: Date.new(2026, 11, 5))

    assert response.success?
    assert_requested stub
  end

  test "rejects exchanges Yahoo is not used for" do
    response = @provider.fetch_security_prices(symbol: "AAPL", exchange_operating_mic: "XNAS", start_date: Date.new(2026, 11, 2), end_date: Date.new(2026, 11, 5))

    assert_not response.success?
  end

  test "latest price comes from the chart meta and is dated by the IST day of the last trade" do
    traded_at = Time.utc(2026, 11, 18, 5, 30).to_i # 11:00 IST
    body = { chart: { result: [ { meta: { currency: "INR", regularMarketPrice: 2931.25, regularMarketTime: traded_at } } ] } }.to_json
    stub = stub_request(:get, @chart_url).with(query: hash_including("range" => "1d", "interval" => "1d")).to_return(status: 200, body: body)

    response = @provider.fetch_latest_price(symbol: "RELIANCE", exchange_operating_mic: "XNSE")

    assert response.success?
    assert_requested stub
    assert_equal Date.new(2026, 11, 18), response.data.date
    assert_equal BigDecimal("2931.25"), response.data.price
    assert_equal "INR", response.data.currency
  end

  test "latest price fails when Yahoo has no quote" do
    stub_request(:get, @chart_url).to_return(status: 200, body: { chart: { result: [ { meta: {} } ] } }.to_json)

    assert_not @provider.fetch_latest_price(symbol: "RELIANCE", exchange_operating_mic: "XNSE").success?
  end

  test "latest price on or before a date" do
    stub_request(:get, @chart_url).to_return(status: 200, body: file_fixture("yahoo_chart_reliance.json").read)

    response = @provider.fetch_security_price(symbol: "RELIANCE", exchange_operating_mic: "XNSE", date: Date.new(2026, 11, 5))

    assert response.success?
    assert_equal Date.new(2026, 11, 5), response.data.date
    assert_equal BigDecimal("2931.0"), response.data.price
  end

  test "returns an error response when Yahoo has no data" do
    stub_request(:get, @chart_url).to_return(status: 200, body: { chart: { result: nil, error: { description: "No data found" } } }.to_json)

    response = @provider.fetch_security_prices(symbol: "RELIANCE", exchange_operating_mic: "XNSE", start_date: Date.new(2026, 11, 2), end_date: Date.new(2026, 11, 5))

    assert_not response.success?
    assert_match "No data found", response.error.message
  end

  test "search keeps only NSE and BSE stocks and ETFs" do
    stub_request(:get, %r{query2\.finance\.yahoo\.com/v1/finance/search}).to_return(status: 200, body: file_fixture("yahoo_search_sample.json").read)

    response = @provider.search_securities("sample")

    assert response.success?
    assert_equal [ [ "RELIANCE", "XNSE", "stock" ], [ "RELIANCE", "XBOM", "stock" ], [ "SAMPLEGOLD", "XNSE", "etf" ] ],
                 response.data.map { |s| [ s.symbol, s.exchange_operating_mic, s.kind ] }
    assert_equal "Sample Industries Limited", response.data.first.name
    assert_equal "SAMPLE GOLD ETF", response.data.last.name
    assert response.data.all? { |s| s.country_code == "IN" }
  end

  test "search can be restricted to one exchange" do
    stub_request(:get, %r{query2\.finance\.yahoo\.com/v1/finance/search}).to_return(status: 200, body: file_fixture("yahoo_search_sample.json").read)

    response = @provider.search_securities("sample", exchange_operating_mic: "XBOM")

    assert_equal [ "XBOM" ], response.data.map(&:exchange_operating_mic).uniq
  end

  test "search is empty for non-Indian countries" do
    assert_empty @provider.search_securities("sample", country_code: "US").data
  end
end
