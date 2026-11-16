require "test_helper"

class GoalAllocationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @goal = goals(:home)
    @account = accounts(:depository)
  end

  test "adds an account allocation" do
    assert_difference "@goal.goal_allocations.count", 1 do
      post goal_goal_allocations_path(@goal), params: { goal_allocation: { target: @account.id, percentage: 40 } }
    end

    assert_redirected_to goal_path(@goal)
    assert_equal 40, @goal.goal_allocations.sole.percentage
    assert_nil @goal.goal_allocations.sole.security_id
  end

  test "adds a holding allocation" do
    holding = holdings(:one)

    assert_difference "@goal.goal_allocations.count", 1 do
      post goal_goal_allocations_path(@goal), params: {
        goal_allocation: { target: "#{holding.account_id}|#{holding.security_id}", percentage: 50 }
      }
    end

    allocation = @goal.goal_allocations.sole
    assert_equal holding.security_id, allocation.security_id
    assert_equal holding.account_id, allocation.account_id
  end

  test "refuses to allocate more than 100 percent across goals" do
    goals(:emergency).goal_allocations.create!(account: @account, percentage: 70)

    assert_no_difference "GoalAllocation.count" do
      post goal_goal_allocations_path(@goal), params: { goal_allocation: { target: @account.id, percentage: 40 } }
    end

    assert_redirected_to goal_path(@goal)
    assert_match "maximum 100%", flash[:alert]
  end

  test "refuses another family's account" do
    other_account = families(:empty).accounts.create!(name: "Other", balance: 100, currency: "USD", accountable: Depository.new)

    assert_no_difference "GoalAllocation.count" do
      post goal_goal_allocations_path(@goal), params: { goal_allocation: { target: other_account.id, percentage: 40 } }
    end

    assert_redirected_to goal_path(@goal)
  end

  test "removes an allocation" do
    allocation = @goal.goal_allocations.create!(account: @account, percentage: 40)

    assert_difference "@goal.goal_allocations.count", -1 do
      delete goal_goal_allocation_path(@goal, allocation)
    end

    assert_redirected_to goal_path(@goal)
  end

  test "cannot touch another family's goal" do
    other = families(:empty).goals.create!(name: "Not yours", currency: "USD", target_amount: 1000, target_date: 1.year.from_now.to_date)

    post goal_goal_allocations_path(other), params: { goal_allocation: { target: @account.id, percentage: 40 } }

    assert_response :not_found
  end
end
