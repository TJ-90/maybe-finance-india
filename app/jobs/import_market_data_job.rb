# Runs on the schedule in config/schedule.yml:
#   - nightly (full): FX rates, plus prices for everything that is missing
#   - after the NSE/BSE close (scope "exchange_close"): re-fetches the last few days of NSE/BSE closing prices,
#     replacing the intraday prices that were stored while the market was open
#
# The primary purpose of this job is to:
# 1. Determine what exchange rate pairs, security prices, and other market data all of our users need to view historical account balance data
# 2. For each needed rate/price, fetch from our data provider and upsert to our database
#
# Each individual account sync will still fetch any missing market data that isn't yet synced, but by running
# this job daily, we significantly reduce overlapping account syncs that both need the same market data.
#
# Afterwards RefreshInvestmentValuesJob re-syncs the accounts whose prices or rates changed, so holdings,
# net worth and XIRR do not wait for somebody to log in.
class ImportMarketDataJob < ApplicationJob
  queue_as :scheduled

  def perform(opts)
    return unless MarketData.jobs_enabled?

    opts = opts.symbolize_keys
    mode = opts.fetch(:mode, :full)
    clear_cache = opts.fetch(:clear_cache, false)
    started_at = Time.current

    importer = MarketDataImporter.new(mode: mode, clear_cache: clear_cache)

    if opts[:scope].to_s == "exchange_close"
      importer.import_exchange_close_prices
    else
      importer.import_all
    end

    RefreshInvestmentValuesJob.perform_later(since: started_at.iso8601(6))
  end
end
