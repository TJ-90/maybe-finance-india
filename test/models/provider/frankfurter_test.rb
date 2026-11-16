require "test_helper"

class Provider::FrankfurterTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::Frankfurter.new
  end

  test "fetches a single USD to INR rate" do
    stub_request(:get, "https://api.frankfurter.app/2026-11-02")
      .with(query: { from: "USD", to: "INR" })
      .to_return(status: 200, body: { amount: 1.0, base: "USD", date: "2026-10-30", rates: { INR: 88.1 } }.to_json)

    response = @provider.fetch_exchange_rate(from: "USD", to: "INR", date: Date.new(2026, 11, 2))

    assert response.success?
    assert_equal Date.new(2026, 11, 2), response.data.date
    assert_equal BigDecimal("88.1"), response.data.rate
    assert_equal "USD", response.data.from
    assert_equal "INR", response.data.to
  end

  test "fetches a range of rates" do
    stub_request(:get, "https://api.frankfurter.app/2026-11-02..2026-11-06")
      .with(query: { from: "USD", to: "INR" })
      .to_return(status: 200, body: file_fixture("frankfurter_range_usd_inr.json").read)

    response = @provider.fetch_exchange_rates(from: "USD", to: "INR", start_date: Date.new(2026, 11, 2), end_date: Date.new(2026, 11, 6))

    assert response.success?
    assert_equal 5, response.data.size
    assert_equal Date.new(2026, 11, 2), response.data.first.date
    assert_equal BigDecimal("88.5"), response.data.last.rate
  end

  test "splits long ranges into windows so Frankfurter keeps daily granularity" do
    first = stub_request(:get, "https://api.frankfurter.app/2026-01-01..2026-03-26").with(query: { from: "USD", to: "INR" })
      .to_return(status: 200, body: { rates: { "2026-01-02" => { INR: 85.0 } } }.to_json)
    second = stub_request(:get, "https://api.frankfurter.app/2026-03-27..2026-05-01").with(query: { from: "USD", to: "INR" })
      .to_return(status: 200, body: { rates: { "2026-03-27" => { INR: 86.0 } } }.to_json)

    response = @provider.fetch_exchange_rates(from: "USD", to: "INR", start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 5, 1))

    assert response.success?
    assert_equal [ Date.new(2026, 1, 2), Date.new(2026, 3, 27) ], response.data.map(&:date)
    assert_requested first
    assert_requested second
  end

  test "returns an error response for unsupported currencies" do
    stub_request(:get, "https://api.frankfurter.app/2026-11-02").with(query: { from: "USD", to: "XYZ" })
      .to_return(status: 404, body: { message: "not found" }.to_json)

    response = @provider.fetch_exchange_rate(from: "USD", to: "XYZ", date: Date.new(2026, 11, 2))

    assert_not response.success?
  end

  test "ExchangeRate importer stores USD to INR rates from Frankfurter" do
    stub_request(:get, %r{api\.frankfurter\.app/\d{4}-\d{2}-\d{2}\.\.\d{4}-\d{2}-\d{2}}).with(query: { from: "USD", to: "INR" }).to_return do |request|
      range = request.uri.path.delete_prefix("/")
      start_date = Date.iso8601(range.split("..").first)
      rates = (start_date..start_date + 9).reject { |d| d.saturday? || d.sunday? }.index_with { { INR: 88.0 } }
      { status: 200, body: { base: "USD", rates: rates.transform_keys(&:to_s) }.to_json }
    end

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil do
      assert_instance_of Provider::Frankfurter, ExchangeRate.provider

      ExchangeRate.delete_all
      ExchangeRate.import_provider_rates(from: "USD", to: "INR", start_date: 3.days.ago.to_date, end_date: Date.current)

      assert_equal 4, ExchangeRate.where(from_currency: "USD", to_currency: "INR").count
      assert_equal BigDecimal("88.0"), ExchangeRate.find_by(from_currency: "USD", to_currency: "INR", date: Date.current).rate
    end
  end
end
