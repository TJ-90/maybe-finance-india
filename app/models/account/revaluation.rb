# Queues account syncs so that holdings, balances, net worth and XIRR pick up fresh prices and rates.
#
# Idempotent and cheap: each account gets at most one sync per run, and an account that already has a
# pending or running sync is left to it (Syncable#sync_later only widens that sync's window).
class Account::Revaluation
  # Accounts that currently hold (net positive units of) any of the securities
  def self.accounts_holding(security_ids)
    return Account.none if security_ids.blank?

    held = Entry.joins("INNER JOIN trades ON trades.id = entries.entryable_id AND entries.entryable_type = 'Trade'")
                .where(trades: { security_id: security_ids })
                .group("entries.account_id", "trades.security_id")
                .having("SUM(trades.qty) > 0")
                .pluck("entries.account_id")

    Account.visible.where(id: held.uniq)
  end

  # Accounts kept in a currency other than their family's, among accounts using one of `currencies`
  def self.accounts_in_currencies(currencies)
    return Account.none if currencies.blank?

    Account.visible.joins(:family).where(currency: currencies).where("accounts.currency <> families.currency")
  end

  # window_starts: { account_id => earliest date whose value may have changed }
  def initialize(window_starts)
    @window_starts = window_starts
  end

  # Adds the accounts of a scope, keeping the earliest window start when an account is listed twice
  def self.collect(*scopes_with_dates)
    window_starts = {}

    scopes_with_dates.each do |scope, date|
      scope.pluck(:id).each { |id| window_starts[id] = [ window_starts[id], date ].compact.min }
    end

    new(window_starts)
  end

  # Returns the number of accounts a sync was requested for
  def run
    count = 0

    Account.where(id: window_starts.keys).find_each do |account|
      account.sync_later(window_start_date: window_starts[account.id])
      count += 1
    end

    count
  end

  private
    attr_reader :window_starts
end
