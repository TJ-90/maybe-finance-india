require "test_helper"

class Assistant::Function::GetGoalsTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
  end

  test "returns each goal with projection figures" do
    result = Assistant::Function::GetGoals.new(@user).call
    names = result[:goals].map { |g| g[:name] }

    assert_includes names, "Home down payment"
    goal = result[:goals].find { |g| g[:name] == "Home down payment" }
    assert_equal "home", goal[:kind]
    assert_includes [ true, false ], goal[:on_track]
    assert goal[:required_monthly_sip].present?
    assert goal[:assumptions][:inflation_rate_percent].positive?
    assert_kind_of Array, goal[:rebalancing]
  end

  test "includes allocated value from linked accounts" do
    goal = goals(:home)
    goal.goal_allocations.create!(account: accounts(:depository), percentage: 100)

    result = Assistant::Function::GetGoals.new(@user).call
    entry = result[:goals].find { |g| g[:name] == goal.name }

    assert_equal goal.reload.allocated_value.format, entry[:allocated_value]
  end

  test "no goals gives an empty list" do
    @family.goals.destroy_all

    assert_empty Assistant::Function::GetGoals.new(@user).call[:goals]
  end

  test "all three India functions are registered with the assistant" do
    functions = Assistant.config_for(chats(:two))[:functions]

    [ Assistant::Function::GetGoals, Assistant::Function::GetTaxSummary, Assistant::Function::GetHoldings ].each do |klass|
      assert_includes functions, klass
    end
  end
end
