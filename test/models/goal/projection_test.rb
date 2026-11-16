require "test_helper"

# Expected values are computed independently of the app code (closed-form SIP and annuity
# formulas); the comment above each test shows the formula.
class Goal::ProjectionTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 11, 16)

  def build_goal(**attrs)
    Goal.new({
      family: families(:dylan_family),
      name: "Test",
      kind: "custom",
      currency: "INR",
      target_amount: 1_000_000,
      target_date: Date.new(2036, 11, 16),
      inflation_rate: 6,
      expected_equity_return: 12,
      expected_debt_return: 7,
      monthly_sip: 0,
      sip_step_up_pct: 0,
      initial_equity_pct: 100,
      final_equity_pct: 100,
      glide_path_years: 0
    }.merge(attrs))
  end

  def projection_for(goal, current_value: 0)
    Goal::Projection.new(goal, today: TODAY, current_value: current_value)
  end

  test "counts whole months to the target date" do
    assert_equal 120, projection_for(build_goal).months_to_target
    assert_equal 119, projection_for(build_goal(target_date: Date.new(2036, 11, 15))).months_to_target
    assert_equal 0, projection_for(build_goal(target_date: Date.new(2025, 1, 1))).months_to_target
  end

  # 1,000,000 * 1.06^10
  test "inflates the target to the target date" do
    projection = projection_for(build_goal)

    assert_in_delta 1_000_000, projection.target_today, 0.001
    assert_in_delta 1_790_847.70, projection.inflation_adjusted_target, 0.01
  end

  # sip * ((1+m)^n - 1)/m * (1+m) with m = 1.12^(1/12) - 1, n = 120
  test "SIP future value without step-up" do
    projection = projection_for(build_goal(monthly_sip: 10_000))

    assert_in_delta 2_240_358.90, projection.projected_corpus, 0.05
  end

  # 10,000 * A(12) * 1.12 + 11,000 * A(12), A(12) = annuity-due factor for 12 months
  test "SIP future value with a 10 percent yearly step-up" do
    goal = build_goal(monthly_sip: 10_000, sip_step_up_pct: 10, target_date: Date.new(2028, 11, 16))

    assert_in_delta 283_416.25, projection_for(goal).projected_corpus, 0.05
  end

  # Three blocks of 12 months: 10,000, 11,000 and 12,100
  test "step-up compounds every year" do
    goal = build_goal(monthly_sip: 10_000, sip_step_up_pct: 10, target_date: Date.new(2029, 11, 16))

    assert_in_delta 471_900.83, projection_for(goal).projected_corpus, 0.05
  end

  # 100,000 at a 50/50 blend of 12% and 7% = 9.5% a year for 10 years
  test "allocated value grows at the blended return" do
    goal = build_goal(initial_equity_pct: 50, final_equity_pct: 50)

    assert_in_delta 247_822.76, projection_for(goal, current_value: 100_000).projected_corpus, 0.05
  end

  test "glide path lowers the blended return as the target nears" do
    flat = build_goal(initial_equity_pct: 100, final_equity_pct: 100)
    gliding = build_goal(initial_equity_pct: 100, final_equity_pct: 0, glide_path_years: 5)

    gliding_corpus = projection_for(gliding, current_value: 100_000).projected_corpus

    assert_operator gliding_corpus, :<, projection_for(flat, current_value: 100_000).projected_corpus
    assert_operator gliding_corpus, :>, 100_000 * 1.07**10
  end

  test "shortfall and surplus" do
    projection = projection_for(build_goal(monthly_sip: 10_000))

    assert projection.on_track?
    assert_in_delta 2_240_358.90 - 1_790_847.70, projection.surplus, 0.1
    assert_equal 0, projection.shortfall

    short = projection_for(build_goal(monthly_sip: 1_000))

    assert_not short.on_track?
    assert_in_delta 1_790_847.70 - 224_035.89, short.shortfall, 0.1
    assert_equal 0, short.surplus
  end

  test "progress is allocated value over the inflation-adjusted target, capped at 100" do
    assert_in_delta 5.58, projection_for(build_goal, current_value: 100_000).progress_pct, 0.01
    assert_equal 100, projection_for(build_goal, current_value: 99_000_000).progress_pct
  end

  # With post-retirement return equal to inflation the annuity-due value is P1 * n, where
  # P1 = 50,000 * 12 * 1.06^30 and n = 25 years
  test "retirement corpus when returns equal inflation" do
    projection = projection_for(retirement_goal(post_retirement_return: 6))

    assert_in_delta 86_152_367.59, projection.retirement_corpus, 0.1
    assert_in_delta 86_152_367.59, projection.inflation_adjusted_target, 0.1
    assert_in_delta 86_152_367.59 / 1.06**30, projection.target_today, 0.1
  end

  # Sum over k = 0..24 of P1 * (1.06/1.08)^k, with P1 = 600,000 * 1.06^30
  test "retirement corpus is the present value of a growing annuity" do
    assert_in_delta 69_468_932.61, projection_for(retirement_goal).retirement_corpus, 0.1
  end

  test "growing annuity handles zero periods" do
    assert_equal 0, Goal::Projection.growing_annuity_due_value(first_payment: 100, growth: 0.05, discount: 0.08, periods: 0)
  end

  test "required SIP lands on the target within 0.1 percent" do
    goal = build_goal(target_amount: 5_000_000, sip_step_up_pct: 10, initial_equity_pct: 70, final_equity_pct: 30, glide_path_years: 5)
    required = projection_for(goal, current_value: 200_000).required_monthly_sip

    assert_operator required, :>, 0

    goal.monthly_sip = required
    reached = projection_for(goal, current_value: 200_000)

    assert_in_delta reached.inflation_adjusted_target, reached.projected_corpus, reached.inflation_adjusted_target * 0.001
  end

  test "required SIP round trip without step-up" do
    goal = build_goal(target_amount: 2_500_000)
    required = projection_for(goal).required_monthly_sip

    goal.monthly_sip = required
    reached = projection_for(goal)

    assert_in_delta reached.inflation_adjusted_target, reached.projected_corpus, reached.inflation_adjusted_target * 0.001
  end

  test "required SIP round trip for retirement" do
    goal = retirement_goal(initial_equity_pct: 80, final_equity_pct: 30, glide_path_years: 8, sip_step_up_pct: 8)
    required = projection_for(goal, current_value: 1_000_000).required_monthly_sip

    goal.monthly_sip = required
    reached = projection_for(goal, current_value: 1_000_000)

    assert_in_delta reached.retirement_corpus, reached.projected_corpus, reached.retirement_corpus * 0.001
  end

  test "required SIP is lower with a step-up" do
    flat = projection_for(build_goal(sip_step_up_pct: 0)).required_monthly_sip
    stepped = projection_for(build_goal(sip_step_up_pct: 10)).required_monthly_sip

    assert_operator stepped, :<, flat
  end

  test "required SIP is zero when allocated value already reaches the target" do
    assert_equal 0, projection_for(build_goal, current_value: 5_000_000).required_monthly_sip
  end

  test "required SIP is unknown once the date has passed" do
    assert_nil projection_for(build_goal(target_date: Date.new(2026, 1, 1))).required_monthly_sip
  end

  test "chart data pairs projected corpus with the inflating target" do
    points = projection_for(build_goal(monthly_sip: 10_000)).chart_data[:points]

    assert_equal "2026-11-16", points.first[:date]
    assert_equal "2036-11-16", points.last[:date]
    assert_equal 1_000_000, points.first[:target]
    assert_equal 1_790_848, points.last[:target]
    assert_equal "₹17.91 L", points.last[:target_formatted]
  end

  private
    def retirement_goal(**attrs)
      build_goal(**{
        kind: "retirement",
        target_amount: 0,
        current_age: 30,
        retirement_age: 60,
        life_expectancy: 85,
        monthly_expenses_today: 50_000,
        post_retirement_return: 8,
        target_date: Date.new(2056, 11, 16)
      }.merge(attrs))
    end
end
