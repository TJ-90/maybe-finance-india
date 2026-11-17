# What one holding has returned, all in the account currency:
#
#   invested                       FIFO cost of the units still held
#   current_value, gain            value now, and value minus invested
#   absolute_return                gain as a fraction of invested (0.1 = 10%)
#   xirr                           annualized, money-weighted (see Xirr)
#   one_day_change(_percent)       latest price against the one before it
#   cagr_since_first_purchase      price based: (latest price / price on the first purchase date) ^ (1 / years) - 1,
#                                  nil until the security has been held for a year
#
# Reuses the account's tax lots, so a page of holdings replays the trades once (see Account::Returns#tax_lots;
# make the holdings share one account instance).
class Holding::Returns
  MIN_CAGR_YEARS = 1
  START_PRICE_GAP_DAYS = 7
  DAYS_IN_YEAR = 365.25

  def initialize(holding)
    @holding = holding
  end

  def invested
    @invested ||= Money.new(open_lots.sum(&:cost), holding.currency)
  end

  def current_value
    holding.amount_money
  end

  def gain
    current_value - invested
  end

  # As a fraction of invested, nil when nothing is invested
  def absolute_return
    return nil if invested.amount.zero?

    gain.amount / invested.amount
  end

  def xirr
    holding.xirr
  end

  # Change in value since the previous price (Money, in the account currency), nil without a previous price
  def one_day_change
    percent = one_day_change_percent
    return nil if percent.nil? || current_value.nil?

    current_value * (percent / (1 + percent))
  end

  # Fraction, from the latest stored price against the one before it
  def one_day_change_percent
    return @one_day_change_percent if defined?(@one_day_change_percent)

    latest = latest_price
    previous = latest && security.prices.where(currency: latest.currency, date: ...latest.date).order(date: :desc).pick(:price)

    @one_day_change_percent = previous.nil? || previous.zero? ? nil : latest.price / previous - 1
  end

  def first_purchase_date
    return @first_purchase_date if defined?(@first_purchase_date)

    dates = open_lots.map(&:buy_date) + account.tax_lots.realized_lots.select { |lot| lot.security.id == security.id }.map(&:buy_date)
    @first_purchase_date = dates.min
  end

  # Whole and fractional years since the first purchase
  def years_held
    return nil if first_purchase_date.nil?

    (holding.date - first_purchase_date).to_i / DAYS_IN_YEAR
  end

  # Fraction (0.12 = 12% a year), or nil when held under a year or when no price is known for the first day
  def cagr_since_first_purchase
    return @cagr if defined?(@cagr)

    @cagr = compute_cagr
  end

  private
    attr_reader :holding

    delegate :security, :account, to: :holding

    def open_lots
      @open_lots ||= account.tax_lots.open_lots.select { |lot| lot.security.id == security.id }
    end

    def latest_price
      return @latest_price if defined?(@latest_price)

      @latest_price = security.prices.where(date: ..holding.date).order(date: :desc).first
    end

    def compute_cagr
      years = years_held
      latest = latest_price
      return nil if years.nil? || years < MIN_CAGR_YEARS || latest.nil?

      start = start_price(latest.currency)
      return nil if start.nil? || start.zero?

      ((latest.price / start)**(1.0 / years) - 1).to_f
    end

    # The stored price on (or just before) the first purchase date. Failing that, what was paid per unit,
    # when that is in the same currency as the prices.
    def start_price(currency)
      stored = security.prices.where(currency: currency, date: (first_purchase_date - START_PRICE_GAP_DAYS.days)..first_purchase_date).order(date: :desc).pick(:price)
      return stored if stored

      first_lot = open_lots.min_by(&:buy_date)
      first_lot.cost_per_unit if first_lot && first_lot.buy_date == first_purchase_date && currency == account.currency
    end
end
