require "test_helper"

class GoalAllocationTest < ActiveSupport::TestCase
  setup do
    @home = goals(:home)
    @emergency = goals(:emergency)
    @account = accounts(:depository)
  end

  test "allocations of one account across goals can total 100" do
    @home.goal_allocations.create!(account: @account, percentage: 60)
    assert @emergency.goal_allocations.new(account: @account, percentage: 40).valid?
  end

  test "allocations of one account across goals cannot exceed 100" do
    @home.goal_allocations.create!(account: @account, percentage: 60)

    allocation = @emergency.goal_allocations.new(account: @account, percentage: 50)

    assert_not allocation.valid?
    assert_match "110", allocation.errors[:percentage].to_sentence
  end

  test "updating an allocation does not count itself" do
    allocation = @home.goal_allocations.create!(account: @account, percentage: 60)
    @emergency.goal_allocations.create!(account: @account, percentage: 40)

    allocation.percentage = 60
    assert allocation.valid?

    allocation.percentage = 61
    assert_not allocation.valid?
  end

  test "totals are tracked separately per security" do
    security = Security.create!(ticker: "GOALTEST", exchange_operating_mic: "XNSE", asset_class: "equity")
    other = Security.create!(ticker: "GOALTWO", exchange_operating_mic: "XNSE", asset_class: "equity")
    account = accounts(:investment)

    @home.goal_allocations.create!(account: account, security: security, percentage: 100)

    assert @emergency.goal_allocations.new(account: account, security: other, percentage: 100).valid?
    assert @emergency.goal_allocations.new(account: account, percentage: 100).valid?
    assert_not @emergency.goal_allocations.new(account: account, security: security, percentage: 1).valid?
  end

  test "the same account cannot be allocated twice to one goal" do
    @home.goal_allocations.create!(account: @account, percentage: 10)

    assert_not @home.goal_allocations.new(account: @account, percentage: 10).valid?
  end

  test "percentage must be between 0 and 100" do
    assert_not @home.goal_allocations.new(account: @account, percentage: 0).valid?
    assert_not @home.goal_allocations.new(account: @account, percentage: 101).valid?
  end

  test "account must belong to the goal's family" do
    other_account = families(:empty).accounts.create!(
      name: "Other", balance: 100, currency: "USD", accountable: Depository.new
    )

    allocation = @home.goal_allocations.new(account: other_account, percentage: 10)

    assert_not allocation.valid?
    assert allocation.errors[:account].present?
  end

  test "value of a security allocation is that holding's share" do
    holding = holdings(:one)
    allocation = @home.goal_allocations.create!(account: holding.account, security: holding.security, percentage: 50)

    assert_equal Money.new(holding.amount * 0.5, "USD"), allocation.value
  end

  test "value of an account allocation is the balance share" do
    allocation = @home.goal_allocations.create!(account: @account, percentage: 25)

    assert_equal Money.new(@account.balance * 0.25, "USD"), allocation.value
  end
end
