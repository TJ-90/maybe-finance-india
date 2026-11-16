# Projects whether a goal is on track. All math is done in floats on the goal's own currency and
# only wrapped in Money at the edges; the plan is an estimate, not an accounting figure.
#
# Conventions (documented because they change the numbers):
#   * The SIP is invested at the start of each month, then the month's return is earned.
#   * The SIP steps up once every 12 months, starting with the 13th month.
#   * Returns are annual rates converted to a compounding monthly rate, blended by the glide path's
#     equity share on the month's last day.
#   * Retirement expenses are paid at the start of each retirement year (annuity due), which is the
#     cautious choice.
class Goal::Projection
  Point = Data.define(:date, :projected, :target)

  attr_reader :goal, :today

  # `current_value` is the money already allocated to the goal (amount in the goal currency). It is
  # injectable so the math can be tested without any accounts.
  def initialize(goal, today: Date.current, current_value: nil)
    @goal = goal
    @today = today
    @current_value = current_value
  end

  def currency
    goal.currency
  end

  def months_to_target
    @months_to_target ||= begin
      months = (goal.target_date.year - today.year) * 12 + (goal.target_date.month - today.month)
      months -= 1 if goal.target_date.day < today.day
      [ months, 0 ].max
    end
  end

  def years_to_target
    months_to_target / 12.0
  end

  def inflation_factor(years = years_to_target)
    (1 + rate(goal.inflation_rate))**years
  end

  # Target in today's money. For retirement this is the corpus needed, discounted back to today.
  def target_today
    return retirement_corpus / inflation_factor if goal.retirement?

    goal.target_amount.to_f
  end

  # What the target costs on the target date once inflation is added
  def inflation_adjusted_target
    return retirement_corpus if goal.retirement?

    target_today * inflation_factor
  end

  # Corpus needed on the retirement date: the present value of annual expenses that grow with
  # inflation for (life expectancy - retirement age) years, funded at the post-retirement return.
  def retirement_corpus
    return 0.0 unless goal.retirement?

    first_year_expense = goal.monthly_expenses_today.to_f * 12 * inflation_factor
    years = goal.life_expectancy - goal.retirement_age

    self.class.growing_annuity_due_value(
      first_payment: first_year_expense,
      growth: rate(goal.inflation_rate),
      discount: rate(goal.post_retirement_return),
      periods: years
    )
  end

  # Present value of `periods` payments that start at `first_payment` and grow by `growth` a period,
  # with each payment made at the start of its period.
  def self.growing_annuity_due_value(first_payment:, growth:, discount:, periods:)
    return 0.0 if periods <= 0

    ordinary =
      if (discount - growth).abs < 1e-12
        first_payment * periods / (1 + discount)
      else
        first_payment * (1 - ((1 + growth) / (1 + discount))**periods) / (discount - growth)
      end

    ordinary * (1 + discount)
  end

  def current_value
    @current_value ||= goal.allocated_value.amount.to_f
  end

  # Corpus on the target date with the goal's current SIP
  def projected_corpus
    simulate(goal.monthly_sip.to_f).last
  end

  # Positive when the projection falls short of the target
  def shortfall
    [ inflation_adjusted_target - projected_corpus, 0.0 ].max
  end

  def surplus
    [ projected_corpus - inflation_adjusted_target, 0.0 ].max
  end

  def on_track?
    projected_corpus >= inflation_adjusted_target - 0.005
  end

  # Percentage of the inflation-adjusted target already covered by allocated money, capped at 100
  def progress_pct
    target = inflation_adjusted_target
    return 100.0 if target <= 0

    [ [ current_value / target * 100, 0.0 ].max, 100.0 ].min
  end

  # The starting monthly SIP (before step-ups) that lands exactly on the target, found by
  # bisection. Zero when the allocated money alone gets there; nil when the date has passed.
  def required_monthly_sip
    target = inflation_adjusted_target
    return 0.0 if simulate(0.0).last >= target
    return nil if months_to_target.zero?

    low = 0.0
    high = target # a SIP equal to the whole target in month one is always enough

    200.times do
      mid = (low + high) / 2
      simulate(mid).last >= target ? high = mid : low = mid
      break if high - low < 1e-7
    end

    high
  end

  # Month-by-month corpus, starting with today's value
  def simulate(monthly_sip)
    value = current_value
    values = [ value ]
    glide_path = goal.glide_path

    months_to_target.times do |index|
      month = index + 1
      sip = monthly_sip * (1 + rate(goal.sip_step_up_pct))**(index / 12)
      date = today >> month

      value = (value + sip) * (1 + monthly_return(glide_path.equity_pct_for(date)))
      values << value
    end

    values
  end

  # Chart data: projected corpus against the target as it inflates
  def series
    projected = simulate(goal.monthly_sip.to_f)
    base_target = target_today

    projected.each_with_index.map do |value, month|
      Point.new(
        date: today >> month,
        projected: value,
        target: base_target * inflation_factor(month / 12.0)
      )
    end
  end

  # JSON for the goal chart. Money is formatted here so the browser never formats it; the series is
  # thinned to at most ~120 points.
  def chart_data(max_points: 120)
    points = series
    step = [ points.size / max_points, 1 ].max

    sampled = points.each_with_index.select { |_point, index| (index % step).zero? || index == points.size - 1 }.map(&:first)

    {
      points: sampled.map do |point|
        {
          date: point.date.iso8601,
          date_formatted: point.date.strftime("%b %Y"),
          projected: point.projected.round,
          target: point.target.round,
          projected_formatted: money(point.projected).format_compact,
          target_formatted: money(point.target).format_compact
        }
      end
    }
  end

  def money(amount)
    Money.new(amount, currency)
  end

  private
    def rate(percent)
      percent.to_f / 100
    end

    # Monthly compounding rate for a portfolio with the given equity share (in percent)
    def monthly_return(equity_pct)
      equity = equity_pct / 100
      annual = equity * rate(goal.expected_equity_return) + (1 - equity) * rate(goal.expected_debt_return)

      (1 + annual)**(1.0 / 12) - 1
    end
end
