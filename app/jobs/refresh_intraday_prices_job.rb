# Runs every 15 minutes (see config/schedule.yml) and only does work during the NSE/BSE session
# (weekdays 09:15-15:30 IST). Turn off with INTRADAY_PRICE_REFRESH=false.
class RefreshIntradayPricesJob < ApplicationJob
  queue_as :scheduled

  def perform
    return unless MarketData.jobs_enabled? && MarketData.intraday_enabled? && MarketData.market_open?
    return if Security.provider.nil?

    started_at = Time.current
    changed_ids = Security::IntradayRefresh.new.refresh
    return if changed_ids.empty?

    Account::Revaluation.collect(
      [ Account::Revaluation.accounts_holding(changed_ids), Time.current.in_time_zone(MarketData::TIME_ZONE).to_date ]
    ).run

    Rails.logger.info("Intraday price refresh updated #{changed_ids.size} securities (started #{started_at.iso8601})")
  end
end
