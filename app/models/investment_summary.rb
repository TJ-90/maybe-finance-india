# Invested / current value / gain / XIRR for a set of investment accounts, in the family currency.
# Invested is the FIFO cost of the units still held.
class InvestmentSummary
  attr_reader :family, :accounts

  def initialize(family:, accounts:)
    @family = family
    @accounts = accounts.to_a
  end

  def any?
    accounts.any? && (invested.positive? || current_value.positive?)
  end

  def invested
    @invested ||= Money.new(Holding::TaxLots.new(accounts, currency: family.currency).open_lots.sum(&:cost), family.currency)
  end

  def current_value
    @current_value ||= Money.new(
      accounts.sum { |a| Money.new(a.securities_value, a.currency).exchange_to(family.currency, fallback_rate: 1).amount },
      family.currency
    )
  end

  def gain
    current_value - invested
  end

  # As a fraction of invested (0.1 = 10%)
  def gain_percent
    return nil if invested.amount.zero?

    gain.amount / invested.amount
  end

  def xirr
    return @xirr if defined?(@xirr)

    @xirr = family.portfolio_xirr(accounts: accounts)
  end
end
