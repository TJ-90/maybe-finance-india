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

  # Net worth split into market assets, retirement funds, cash, property & vehicles, other and liabilities.
  # `owner` limits it to one person's accounts: a HouseholdMember, :joint for accounts that belong to
  # nobody, or nil for everyone.
  def india_breakdown(owner: nil)
    @india_breakdowns ||= {}
    @india_breakdowns[owner.respond_to?(:id) ? owner.id : owner] ||= build_india_breakdown(owner)
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

    def build_india_breakdown(owner)
      assets = owned_by(account_totals.asset_accounts, owner)
      liabilities_total = owner.nil? ? liabilities.total : Money.new(owned_by(account_totals.liability_accounts, owner).sum(&:converted_balance), family.currency)

      IndiaBreakdown.new(asset_accounts: assets, liabilities_total: liabilities_total, currency: family.currency)
    end

    def owned_by(rows, owner)
      return rows if owner.nil?

      owner_id = owner == :joint ? nil : owner.id
      rows.select { |row| row.household_member_id == owner_id }
    end

    def account_totals
      @account_totals ||= AccountTotals.new(family, sync_status_monitor: sync_status_monitor)
    end

    def net_worth_series_builder
      @net_worth_series_builder ||= NetWorthSeriesBuilder.new(family)
    end
end
