require "test_helper"

class Goal::RebalancerTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @goal = goals(:home)
    @goal.update!(initial_equity_pct: 60, final_equity_pct: 60, glide_path_years: 0)
  end

  test "account types map to asset classes" do
    @goal.goal_allocations.create!(account: accounts(:fixed_deposit), percentage: 100)      # 100,000 debt
    @goal.goal_allocations.create!(account: accounts(:provident_fund), percentage: 50)      # 100,000 debt
    @goal.goal_allocations.create!(account: accounts(:depository), percentage: 100)         # 5,000 debt
    @goal.goal_allocations.create!(account: accounts(:precious_metal), percentage: 50)      # 150,000 gold
    @goal.goal_allocations.create!(account: accounts(:other_asset), percentage: 100)        # 550 other

    amounts = @goal.rebalancer.amounts

    assert_equal 205_000, amounts[:debt]
    assert_equal 150_000, amounts[:gold]
    assert_equal 550, amounts[:other]
    assert_equal 0, amounts[:equity]
  end

  test "holdings use the security's effective asset class" do
    equity = create_security("EQ1", "equity")
    hybrid = create_security("HY1", "hybrid")
    account = accounts(:investment)
    account.holdings.destroy_all
    create_holding(account, equity, 8_000)
    create_holding(account, hybrid, 2_000)

    @goal.goal_allocations.create!(account: account, percentage: 100)
    amounts = @goal.rebalancer.amounts

    assert_equal 9_000, amounts[:equity]
    assert_equal 1_000, amounts[:debt]
  end

  test "a family override changes the asset class used" do
    security = create_security("OVR1", "equity")
    account = accounts(:investment)
    account.holdings.destroy_all
    create_holding(account, security, 1_000)
    @family.family_security_overrides.create!(security: security, asset_class: "gold")

    @goal.goal_allocations.create!(account: account, security: security, percentage: 100)

    assert_equal 1_000, @goal.rebalancer.amounts[:gold]
  end

  test "suggests moving from equity to debt when equity is over target" do
    security = create_security("EQ2", "equity")
    account = accounts(:investment)
    account.holdings.destroy_all
    create_holding(account, security, 10_000)
    @goal.goal_allocations.create!(account: account, security: security, percentage: 100)

    rebalancer = @goal.rebalancer

    assert_in_delta 40, rebalancer.drift, 0.001
    suggestion = rebalancer.suggestions.sole
    assert_equal "equity", suggestion.from
    assert_equal "debt", suggestion.to
    assert_equal Money.new(4_000, "USD"), suggestion.amount
  end

  test "suggests moving from debt to equity when equity is under target" do
    @goal.goal_allocations.create!(account: accounts(:fixed_deposit), percentage: 100)

    suggestion = @goal.rebalancer.suggestions.sole

    assert_equal "debt", suggestion.from
    assert_equal "equity", suggestion.to
    assert_equal Money.new(60_000, "USD"), suggestion.amount
  end

  test "no suggestion within the 5 point threshold" do
    security = create_security("EQ3", "equity")
    account = accounts(:investment)
    account.holdings.destroy_all
    create_holding(account, security, 6_200)
    @goal.goal_allocations.create!(account: account, security: security, percentage: 100)
    @goal.goal_allocations.create!(account: accounts(:depository), percentage: 100) # 5,000 debt

    # 6,200 / 11,200 = 55.4% equity against a 60% target
    rebalancer = @goal.rebalancer

    assert_in_delta(-4.64, rebalancer.drift, 0.01)
    assert_empty rebalancer.suggestions
  end

  test "no suggestions without allocations" do
    assert_empty @goal.rebalancer.suggestions
    assert_equal 0, @goal.rebalancer.total
  end

  private
    def create_security(ticker, asset_class)
      Security.create!(ticker: ticker, exchange_operating_mic: "XNSE", asset_class: asset_class)
    end

    def create_holding(account, security, amount)
      account.holdings.create!(security: security, date: Date.current, qty: 1, price: amount, amount: amount, currency: account.currency)
    end
end
