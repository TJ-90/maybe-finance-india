# Trailing 1Y / 3Y / 5Y CAGR from a price (NAV) history: (latest price / price N years earlier) ^ (1 / N) - 1.
# Price based, so it ignores when and how much a particular investor bought.
#
# A window is only reported when the history reaches back to it: the price used for the start has to be
# within MAX_GAP_DAYS (a weekend or holiday gap) before the date N years ago. Otherwise it is nil.
#
#   Security::TrailingReturns.for_security(security).cagr(3)      # stored security_prices
#   Security::TrailingReturns.from_history([[date, nav], ...])    # a series fetched elsewhere
class Security::TrailingReturns
  YEARS = [ 1, 3, 5 ].freeze
  MAX_GAP_DAYS = 10

  class << self
    def for_security(security)
      latest = security.prices.order(date: :desc).pick(:date, :price, :currency)
      return new(latest: nil, lookup: nil) if latest.nil?

      new(
        latest: latest.first(2),
        lookup: ->(target) { security.prices.where(currency: latest.last).where(date: ..target).order(date: :desc).pick(:date, :price) }
      )
    end

    # pairs: [[date, price], ...] in any order
    def from_history(pairs)
      sorted = pairs.map { |date, price| [ date.to_date, price.to_d ] }.sort_by(&:first)
      return new(latest: nil, lookup: nil) if sorted.empty?

      new(latest: sorted.last, lookup: ->(target) { sorted.reverse_each.find { |date, _| date <= target } })
    end
  end

  def initialize(latest:, lookup:)
    @latest = latest
    @lookup = lookup
  end

  # Annualized return as a fraction (0.12 = 12%), or nil when the history does not reach back far enough
  def cagr(years)
    return nil if latest.nil?

    latest_date, latest_price = latest
    target = latest_date - years.years
    start_date, start_price = lookup.call(target)

    return nil if start_date.nil? || start_price.to_d.zero? || (target - start_date).to_i > MAX_GAP_DAYS

    (latest_price.to_f / start_price.to_f)**(1.0 / years) - 1
  end

  # { 1 => 0.12, 3 => 0.15, 5 => nil }
  def to_h
    YEARS.index_with { |years| cagr(years) }
  end

  # Date of the latest price the figures are based on
  def as_of
    latest&.first
  end

  private
    attr_reader :latest, :lookup
end
