# Extended internal rate of return for dated cash flows (the same definition as Excel's XIRR).
#
#   Xirr.new([[Date.new(2020, 1, 1), -1000], [Date.new(2021, 1, 1), 1100]]).rate # => ~0.1
#
# Flows are [date, amount] pairs with outflows (investments) negative and inflows positive.
# Returns nil when there is no solution: fewer than two flows, flows that all share one sign,
# or a rate that cannot be bracketed.
class Xirr
  DAYS_IN_YEAR = 365.0
  MAX_ITERATIONS = 100
  TOLERANCE = 1e-10
  LOWER_BOUND = -0.999999
  UPPER_BOUND = 1_000_000.0

  def initialize(flows)
    @flows = flows.map { |date, amount| [ date.to_date, amount.to_f ] }.reject { |_, amount| amount.zero? }
  end

  def rate
    return nil if flows.size < 2
    return nil unless flows.any? { |_, a| a.negative? } && flows.any? { |_, a| a.positive? }

    newton || bisection
  end

  private
    attr_reader :flows

    def start_date
      @start_date ||= flows.map(&:first).min
    end

    def years(date)
      (date - start_date).to_i / DAYS_IN_YEAR
    end

    def npv(rate)
      flows.sum { |date, amount| amount / ((1.0 + rate)**years(date)) }
    end

    def derivative(rate)
      flows.sum do |date, amount|
        t = years(date)
        -t * amount / ((1.0 + rate)**(t + 1))
      end
    end

    def newton
      guess = 0.1

      MAX_ITERATIONS.times do
        value = npv(guess)
        slope = derivative(guess)
        return nil if slope.zero? || !slope.finite? || !value.finite?

        next_guess = guess - value / slope
        return nil if !next_guess.finite? || next_guess <= LOWER_BOUND

        return next_guess if (next_guess - guess).abs < TOLERANCE
        guess = next_guess
      end

      nil
    end

    # NPV is monotonic in the rate for a single sign change, so a bracketing search is safe.
    def bisection
      low = LOWER_BOUND
      high = UPPER_BOUND
      f_low = npv(low)
      f_high = npv(high)
      return nil unless f_low.finite? && f_high.finite?
      return nil if f_low.positive? == f_high.positive?

      200.times do
        mid = (low + high) / 2.0
        f_mid = npv(mid)
        return mid if f_mid.abs < TOLERANCE || (high - low).abs < TOLERANCE

        if f_mid.positive? == f_low.positive?
          low = mid
          f_low = f_mid
        else
          high = mid
        end
      end

      (low + high) / 2.0
    end
end
