require "test_helper"

class MarketDataTest < ActiveSupport::TestCase
  test "the market is open on weekdays from 09:15 to 15:30 IST" do
    monday = Time.find_zone("Asia/Kolkata").local(2026, 11, 16)

    assert_not MarketData.market_open?(monday.change(hour: 9, min: 14))
    assert MarketData.market_open?(monday.change(hour: 9, min: 15))
    assert MarketData.market_open?(monday.change(hour: 12))
    assert MarketData.market_open?(monday.change(hour: 15, min: 30))
    assert_not MarketData.market_open?(monday.change(hour: 15, min: 31))
  end

  test "the market is closed at the weekend, judged in IST" do
    saturday = Time.find_zone("Asia/Kolkata").local(2026, 11, 21, 11)
    sunday = Time.find_zone("Asia/Kolkata").local(2026, 11, 22, 11)

    assert_not MarketData.market_open?(saturday)
    assert_not MarketData.market_open?(sunday)
    # 04:00 UTC Monday is 09:30 IST Monday; 21:00 UTC Sunday is already Monday 02:30 IST
    assert MarketData.market_open?(Time.utc(2026, 11, 16, 4, 0))
    assert_not MarketData.market_open?(Time.utc(2026, 11, 15, 21, 0))
    # Friday 04:00 UTC is Friday 09:30 IST; Friday 21:00 UTC is already Saturday 02:30 IST
    assert MarketData.market_open?(Time.utc(2026, 11, 20, 4, 0))
    assert_not MarketData.market_open?(Time.utc(2026, 11, 20, 21, 0))
  end

  test "intraday refresh is on unless INTRADAY_PRICE_REFRESH is false" do
    with_env_overrides INTRADAY_PRICE_REFRESH: nil do
      assert MarketData.intraday_enabled?
    end

    with_env_overrides INTRADAY_PRICE_REFRESH: "false" do
      assert_not MarketData.intraday_enabled?
    end
  end

  test "scheduled jobs run in development only when ENABLE_MARKET_DATA_IN_DEV is true" do
    Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new("development"))

    with_env_overrides ENABLE_MARKET_DATA_IN_DEV: nil do
      assert_not MarketData.jobs_enabled?
    end

    with_env_overrides ENABLE_MARKET_DATA_IN_DEV: "true" do
      assert MarketData.jobs_enabled?
    end
  end
end
