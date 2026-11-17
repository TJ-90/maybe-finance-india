# Re-values accounts after market data changed. Chained after the AMFI NAV import and the NSE/BSE and FX
# imports (nothing else re-syncs accounts overnight), and after an intraday price refresh.
#
# `since` is the time the import started: only prices and exchange rates written at or after it count as
# changed, so the job syncs
#   - every account holding an online security with a price that changed, and
#   - accounts kept in a non-family currency when that currency's rate changed.
# Returns the number of accounts a sync was requested for.
class RefreshInvestmentValuesJob < ApplicationJob
  queue_as :scheduled

  def perform(since: nil)
    since = since.present? ? Time.zone.parse(since.to_s) : 1.hour.ago

    changed_prices = Security::Price.joins(:security).where(securities: { offline: false }).where("security_prices.updated_at >= ?", since)
    changed_rates = ExchangeRate.where("exchange_rates.updated_at >= ?", since)

    Account::Revaluation.collect(
      [ Account::Revaluation.accounts_holding(changed_prices.distinct.pluck(:security_id)), changed_prices.minimum(:date) ],
      [ Account::Revaluation.accounts_in_currencies(changed_rates.distinct.pluck(:from_currency)), changed_rates.minimum(:date) ]
    ).run
  end
end
