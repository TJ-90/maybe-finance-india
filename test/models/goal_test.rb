require "test_helper"

class GoalTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "requires a positive target unless it is a retirement goal" do
    goal = @family.goals.new(name: "Trip", kind: "travel", currency: "USD", target_date: 1.year.from_now.to_date, target_amount: 0)
    assert_not goal.valid?
    assert goal.errors[:target_amount].present?
  end

  test "retirement goal needs ages and expenses, and derives its date" do
    goal = @family.goals.new(name: "Retire", kind: "retirement", currency: "USD")
    assert_not goal.valid?
    assert goal.errors[:current_age].present?
    assert goal.errors[:monthly_expenses_today].present?

    goal.assign_attributes(current_age: 30, retirement_age: 60, life_expectancy: 85, monthly_expenses_today: 50_000)

    assert goal.valid?
    assert_equal Date.current + 30.years, goal.target_date
    assert_equal 0, goal.target_amount
  end

  test "retirement ages must be in order" do
    goal = @family.goals.new(
      name: "Retire", kind: "retirement", currency: "USD", current_age: 60, retirement_age: 55,
      life_expectancy: 50, monthly_expenses_today: 10_000
    )

    assert_not goal.valid?
    assert goal.errors[:retirement_age].present?
    assert goal.errors[:life_expectancy].present?
  end

  test "allocated value sums allocations in the goal currency" do
    goal = goals(:home)
    goal.goal_allocations.create!(account: accounts(:depository), percentage: 50)
    goal.goal_allocations.create!(account: accounts(:fixed_deposit), percentage: 10)

    assert_equal Money.new(2500 + 10000, "USD"), goal.allocated_value
  end

  test "allocated value is zero without allocations" do
    assert_equal Money.new(0, "USD"), goals(:home).allocated_value
  end

  test "average monthly expenses use the last six months of the income statement" do
    goal = goals(:emergency)
    IncomeStatement.any_instance.expects(:expense_totals).with do |args|
      period = args[:period]
      period.end_date == Date.current.beginning_of_month - 1.day &&
        period.start_date == (Date.current.beginning_of_month - 6.months)
    end.returns(OpenStruct.new(total: 60_000))

    assert_equal Money.new(10_000, "USD"), goal.average_monthly_expenses
  end

  test "emergency fund target is months of average expenses" do
    goal = goals(:emergency)
    goal.stubs(:average_monthly_expenses).returns(Money.new(10_000, "USD"))

    assert_equal Money.new(60_000, "USD"), goal.emergency_fund_target
    assert_equal Money.new(90_000, "USD"), goal.emergency_fund_target(months: 9)
  end

  test "destroying a goal removes its allocations" do
    goal = goals(:home)
    goal.goal_allocations.create!(account: accounts(:depository), percentage: 50)

    assert_difference "GoalAllocation.count", -1 do
      goal.destroy!
    end
  end
end
