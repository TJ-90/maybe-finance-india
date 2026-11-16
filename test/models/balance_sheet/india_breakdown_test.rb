require "test_helper"

class BalanceSheet::IndiaBreakdownTest < ActiveSupport::TestCase
  Row = Struct.new(:accountable_type, :subtype, :converted_balance)

  def breakdown(rows, liabilities: 0)
    BalanceSheet::IndiaBreakdown.new(asset_accounts: rows, liabilities_total: liabilities, currency: "INR")
  end

  test "groups accounts by accountable type and subtype" do
    result = breakdown([
      Row.new("Investment", "mutual_fund", 1_000),
      Row.new("Investment", "demat", 500),
      Row.new("FixedDeposit", "fd", 200),
      Row.new("PreciousMetal", "gold", 100),
      Row.new("Crypto", nil, 50),
      Row.new("ProvidentFund", "epf", 400),
      Row.new("Investment", "nps_tier1", 300),
      Row.new("Depository", "savings", 250),
      Row.new("Property", "residential", 5_000),
      Row.new("Vehicle", nil, 700),
      Row.new("OtherAsset", nil, 20)
    ], liabilities: 1_500)

    amounts = result.asset_rows.to_h { |row| [ row.key, row.money.amount ] }

    assert_equal 1_850, amounts[:market_assets] # mutual fund + demat + FD + gold + crypto
    assert_equal 700, amounts[:retirement_funds] # EPF + NPS Tier I
    assert_equal 250, amounts[:cash]
    assert_equal 5_700, amounts[:property_and_vehicles]
    assert_equal 20, amounts[:other]
    assert_equal 8_520, result.total_assets.amount
    assert_equal 1_500, result.liabilities.amount
    assert_equal 7_020, result.net_worth.amount
  end

  test "shows only when there is a market or retirement asset" do
    assert_not breakdown([ Row.new("Depository", "savings", 100), Row.new("Property", nil, 100) ]).show?
    assert breakdown([ Row.new("Investment", "demat", 1) ]).show?
    assert breakdown([ Row.new("ProvidentFund", "ppf", 1) ]).show?
    assert breakdown([ Row.new("Investment", "nps_tier2", 1) ]).show?
  end

  test "weights are shares of total assets" do
    result = breakdown([ Row.new("Investment", "demat", 750), Row.new("Depository", "savings", 250) ])

    assert_equal 75, result.weight(result.asset_rows.first)
  end

  test "an empty family has zero weights and no breakdown" do
    result = breakdown([])

    assert_not result.show?
    assert_equal 0, result.weight(result.asset_rows.first)
    assert_equal 0, result.net_worth.amount
  end

  test "is available from the family balance sheet" do
    sheet = families(:dylan_family).balance_sheet

    assert sheet.india_breakdown.show? # fixtures include an investment, crypto and a provident fund
    assert_equal sheet.net_worth, sheet.india_breakdown.net_worth.amount
  end
end
