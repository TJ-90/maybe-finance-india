require "test_helper"

class ImportMarketDataJobTest < ActiveJob::TestCase
  test "the nightly run imports everything, then re-values accounts" do
    MarketDataImporter.any_instance.expects(:import_all).once
    MarketDataImporter.any_instance.expects(:import_exchange_close_prices).never

    assert_enqueued_with(job: RefreshInvestmentValuesJob) do
      ImportMarketDataJob.perform_now({ "mode" => "full", "clear_cache" => false })
    end
  end

  test "the exchange close run only refreshes NSE/BSE closing prices, then re-values accounts" do
    MarketDataImporter.any_instance.expects(:import_exchange_close_prices).once
    MarketDataImporter.any_instance.expects(:import_all).never

    assert_enqueued_with(job: RefreshInvestmentValuesJob) do
      ImportMarketDataJob.perform_now({ "mode" => "full", "scope" => "exchange_close" })
    end
  end

  test "is skipped in development unless ENABLE_MARKET_DATA_IN_DEV is true" do
    Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new("development"))
    MarketDataImporter.any_instance.expects(:import_all).never

    with_env_overrides ENABLE_MARKET_DATA_IN_DEV: nil do
      assert_no_enqueued_jobs { ImportMarketDataJob.perform_now({ "mode" => "full" }) }
    end
  end

  test "runs in development when ENABLE_MARKET_DATA_IN_DEV is true" do
    Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new("development"))
    MarketDataImporter.any_instance.expects(:import_all).once

    with_env_overrides ENABLE_MARKET_DATA_IN_DEV: "true" do
      ImportMarketDataJob.perform_now({ "mode" => "full" })
    end
  end
end
