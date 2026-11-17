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

  # Same as gain_percent; the name used on the cards
  def absolute_return
    gain_percent
  end

  def xirr
    return @xirr if defined?(@xirr)

    @xirr = family.portfolio_xirr(accounts: accounts)
  end

  # How much the holdings moved in value since their previous price, in the family currency. Nil when no
  # holding has a previous price.
  def one_day_change
    return @one_day_change if defined?(@one_day_change)

    changes = accounts.filter_map { |account| account.one_day_change&.exchange_to(family.currency, fallback_rate: 1) }
    @one_day_change = changes.empty? ? nil : Money.new(changes.sum(&:amount), family.currency)
  end

  # One-day change as a fraction of yesterday's value
  def one_day_change_percent
    change = one_day_change
    return nil if change.nil?

    previous = current_value.amount - change.amount
    previous.positive? ? change.amount / previous : nil
  end

  # When the prices behind the figures were last refreshed (a Time), nil when there are none
  def prices_as_of
    return @prices_as_of if defined?(@prices_as_of)

    @prices_as_of = accounts.filter_map(&:prices_last_updated_at).max
  end
end
