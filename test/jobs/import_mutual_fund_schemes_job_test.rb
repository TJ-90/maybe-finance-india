require "test_helper"

class ImportMutualFundSchemesJobTest < ActiveJob::TestCase
  test "imports AMFI schemes and records latest NAVs for tracked funds" do
    security = Security.create!(ticker: "100001", exchange_operating_mic: "AMFI")
    stub_request(:get, Provider::Amfi::NAVALL_URL).to_return(status: 200, body: file_fixture("navall_sample.txt").read)

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil do
      ImportMutualFundSchemesJob.perform_now
    end

    assert_equal 16, MutualFundScheme.count
    assert_equal Date.new(2026, 11, 1), MutualFundScheme.last_nav_date
    assert_equal BigDecimal("245.1234"), security.prices.find_by!(date: Date.new(2026, 11, 1)).price
  end

  test "leaves existing schemes alone when AMFI is unreachable" do
    stub_request(:get, Provider::Amfi::NAVALL_URL).to_return(status: 503)

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil do
      assert_no_changes "MutualFundScheme.pluck(:scheme_code, :latest_nav, :active).sort" do
        ImportMutualFundSchemesJob.perform_now
      end
    end
  end

  test "does nothing when Indian market data is disabled" do
    with_env_overrides DISABLE_INDIAN_MARKET_DATA: "true" do
      assert_no_difference "MutualFundScheme.count" do
        ImportMutualFundSchemesJob.perform_now
      end
    end

    assert_not_requested :any, Provider::Amfi::NAVALL_URL
  end

  test "is scheduled nightly at 23:30 IST, before the market data import" do
    schedule = YAML.load_file(Rails.root.join("config/schedule.yml"))

    assert_equal "ImportMutualFundSchemesJob", schedule.dig("import_mutual_fund_schemes", "class")
    assert_equal "0 18 * * *", schedule.dig("import_mutual_fund_schemes", "cron")
    assert_equal "30 18 * * *", schedule.dig("import_market_data", "cron")
  end
end
