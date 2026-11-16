class BalanceSheet
  include Monetizable

  monetize :net_worth

  attr_reader :family

  def initialize(family)
    @family = family
  end

  def assets
    @assets ||= ClassificationGroup.new(
      classification: "asset",
      currency: family.currency,
      accounts: account_totals.asset_accounts
    )
  end

  def liabilities
    @liabilities ||= ClassificationGroup.new(
      classification: "liability",
      currency: family.currency,
      accounts: account_totals.liability_accounts
    )
  end

  def classification_groups
    [ assets, liabilities ]
  end

  def account_groups
    [ assets.account_groups, liabilities.account_groups ].flatten
  end

  def net_worth
    assets.total - liabilities.total
  end

  # Net worth split into market assets, retirement funds, cash, property & vehicles, other and liabilities
  def india_breakdown
    @india_breakdown ||= IndiaBreakdown.new(
      asset_accounts: account_totals.asset_accounts,
      liabilities_total: liabilities.total,
      currency: family.currency
    )
  end

  def net_worth_series(period: Period.last_30_days)
    net_worth_series_builder.net_worth_series(period: period)
  end

  def currency
    family.currency
  end

  def syncing?
    sync_status_monitor.syncing?
  end

  private
    def sync_status_monitor
      @sync_status_monitor ||= SyncStatusMonitor.new(family)
    end

    def account_totals
      @account_totals ||= AccountTotals.new(family, sync_status_monitor: sync_status_monitor)
    end

    def net_worth_series_builder
      @net_worth_series_builder ||= NetWorthSeriesBuilder.new(family)
    end
end
