require "test_helper"

class GoalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @goal = goals(:home)
  end

  test "lists goals as cards" do
    get goals_path

    assert_response :success
    assert_select "##{dom_id(@goal)}"
    assert_select "##{dom_id(goals(:emergency))}"
    assert_select "a[href=?]", new_goal_path
  end

  test "does not list another family's goals" do
    other = families(:empty).goals.create!(name: "Not yours", currency: "USD", target_amount: 1000, target_date: 1.year.from_now.to_date)

    get goals_path

    assert_select "##{dom_id(other)}", count: 0
  end

  test "empty state when there are no goals" do
    @family.goals.destroy_all

    get goals_path

    assert_response :success
    assert_match "No goals yet", response.body
  end

  test "shows a goal with no allocations (plan first)" do
    get goal_path(@goal)

    assert_response :success
    assert_match "Required monthly SIP", response.body
    assert_match "Glide path", response.body
    assert_select "[data-controller='goal-chart']"
    assert_match "Allocate accounts or holdings", response.body
  end

  test "shows a retirement goal" do
    goal = @family.goals.create!(
      name: "Retire", kind: "retirement", currency: "USD", current_age: 30, retirement_age: 60,
      life_expectancy: 85, monthly_expenses_today: 50_000
    )

    get goal_path(goal)

    assert_response :success
    assert_match "Corpus needed at retirement", response.body
  end

  test "shows allocations and rebalancing suggestions" do
    @goal.goal_allocations.create!(account: accounts(:fixed_deposit), percentage: 100)

    get goal_path(@goal)

    assert_response :success
    assert_match "HDFC Fixed Deposit", response.body
    assert_match "from debt to equity", response.body
  end

  test "cannot see another family's goal" do
    other = families(:empty).goals.create!(name: "Not yours", currency: "USD", target_amount: 1000, target_date: 1.year.from_now.to_date)

    get goal_path(other)

    assert_response :not_found
  end

  test "new and edit forms render" do
    get new_goal_path
    assert_response :success

    get edit_goal_path(@goal)
    assert_response :success
  end

  test "new emergency fund goal can be prefilled from average expenses" do
    Goal.any_instance.stubs(:average_monthly_expenses).returns(Money.new(40_000, "USD"))

    get new_goal_path(kind: "emergency_fund", use_average_expenses: 1, months: 9)

    assert_response :success
    assert_select "input[name='goal[target_amount]'][value=?]", "360000.00"
  end

  test "creates a goal" do
    assert_difference "@family.goals.count", 1 do
      post goals_path, params: { goal: {
        name: "Car", kind: "vehicle", target_amount: 800_000, currency: "USD",
        target_date: 3.years.from_now.to_date, monthly_sip: 10_000, sip_step_up_pct: 5
      } }
    end

    goal = @family.goals.find_by!(name: "Car")
    assert_redirected_to goal_path(goal)
    assert_equal 800_000, goal.target_amount
    assert_equal 5, goal.sip_step_up_pct
  end

  test "creates a retirement goal without a target amount" do
    assert_difference "@family.goals.count", 1 do
      post goals_path, params: { goal: {
        name: "Retire", kind: "retirement", currency: "USD", target_amount: "",
        current_age: 30, retirement_age: 60, life_expectancy: 85, monthly_expenses_today: 50_000
      } }
    end

    # Date.current follows the family's time zone inside a request, so allow a day either way
    target_date = @family.goals.find_by!(name: "Retire").target_date
    assert_in_delta (Date.current + 30.years).jd, target_date.jd, 1
  end

  test "rejects an invalid goal" do
    assert_no_difference "Goal.count" do
      post goals_path, params: { goal: { name: "", kind: "custom", target_amount: 0, currency: "USD", target_date: 1.year.from_now.to_date } }
    end

    assert_response :unprocessable_entity
  end

  test "updates a goal" do
    patch goal_path(@goal), params: { goal: { name: "Bigger home", monthly_sip: 20_000 } }

    assert_redirected_to goal_path(@goal)
    assert_equal "Bigger home", @goal.reload.name
    assert_equal 20_000, @goal.monthly_sip
  end

  test "rejects an invalid update" do
    patch goal_path(@goal), params: { goal: { target_amount: -5 } }

    assert_response :unprocessable_entity
    assert_not_equal(-5, @goal.reload.target_amount)
  end

  test "destroys a goal" do
    assert_difference "@family.goals.count", -1 do
      delete goal_path(@goal)
    end

    assert_redirected_to goals_path
  end

  test "cannot update or destroy another family's goal" do
    other = families(:empty).goals.create!(name: "Not yours", currency: "USD", target_amount: 1000, target_date: 1.year.from_now.to_date)

    patch goal_path(other), params: { goal: { name: "Mine now" } }
    assert_response :not_found

    assert_no_difference "Goal.count" do
      delete goal_path(other)
    end
    assert_response :not_found
  end

  test "show has an empty status history until there are two daily checks" do
    get goal_path(@goal)

    assert_response :success
    assert_select "#goal-status-history", text: /after a couple of checks/
  end

  test "show charts progress and names the last status change" do
    { 3 => "on_track", 2 => "on_track", 1 => "at_risk", 0 => "at_risk" }.each_with_index do |(days_ago, status), index|
      @goal.goal_snapshots.create!(date: Date.current - days_ago, status: status, progress_pct: 10 + index * 5)
    end

    get goal_path(@goal)

    assert_response :success
    assert_select "#goal-status-history svg polyline[points]"
    assert_select "#last-status-change", text: /on track to at risk/
  end

  test "index shows at risk and off track as their own badges" do
    Goal::Projection.any_instance.stubs(:status).returns("at_risk")
    get goals_path

    assert_select "##{dom_id(@goal)}", text: /At risk/
  end
end
