# Net worth split the way Indian households think about it: market-linked assets, retirement funds,
# cash, property and vehicles, other assets, liabilities. Classification uses only the accountable
# type and subtype (not securities data), so it works whatever market data is available.
class BalanceSheet::IndiaBreakdown
  RETIREMENT_INVESTMENT_SUBTYPES = %w[nps_tier1 nps_tier2].freeze

  Row = Data.define(:key, :label, :money, :color, :account_count)

  CATEGORIES = [
    { key: :market_assets, label: "Market assets", color: "#1570EF" },
    { key: :retirement_funds, label: "Retirement funds", color: "#0E9384" },
    { key: :cash, label: "Cash", color: "#12B76A" },
    { key: :property_and_vehicles, label: "Property & vehicles", color: "#06AED4" },
    { key: :other, label: "Other", color: "#7C3AED" }
  ].freeze

  attr_reader :currency

  # asset_accounts: rows responding to #accountable_type, #subtype and #converted_balance (in `currency`)
  def initialize(asset_accounts:, liabilities_total:, currency:)
    @asset_accounts = asset_accounts
    @liabilities_total = liabilities_total
    @currency = currency
  end

  def category_for(account)
    case account.accountable_type
    when "Investment"
      RETIREMENT_INVESTMENT_SUBTYPES.include?(account.subtype) ? :retirement_funds : :market_assets
    when "FixedDeposit", "PreciousMetal", "Crypto"
      :market_assets
    when "ProvidentFund"
      :retirement_funds
    when "Depository"
      :cash
    when "Property", "Vehicle"
      :property_and_vehicles
    else
      :other
    end
  end

  def asset_rows
    @asset_rows ||= CATEGORIES.map do |category|
      accounts = grouped_accounts.fetch(category[:key], [])

      Row.new(
        key: category[:key],
        label: category[:label],
        money: Money.new(accounts.sum(&:converted_balance), currency),
        color: category[:color],
        account_count: accounts.size
      )
    end
  end

  def total_assets
    Money.new(asset_rows.sum { |row| row.money.amount }, currency)
  end

  def liabilities
    Money.new(liabilities_total, currency)
  end

  def net_worth
    total_assets - liabilities
  end

  # Share of total assets, 0..100
  def weight(row)
    return 0 if total_assets.amount.zero?

    row.money.amount / total_assets.amount * 100
  end

  # Only worth showing once the family holds market-linked or retirement assets
  def show?
    grouped_accounts.key?(:market_assets) || grouped_accounts.key?(:retirement_funds)
  end

  private
    attr_reader :asset_accounts, :liabilities_total

    def grouped_accounts
      @grouped_accounts ||= asset_accounts.group_by { |account| category_for(account) }
    end
end
