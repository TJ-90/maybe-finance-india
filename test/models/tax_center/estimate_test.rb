require "test_helper"

class TaxCenter::EstimateTest < ActiveSupport::TestCase
  setup do
    @rules = TaxCenter::Rules.current
  end

  def gain(category, buy, sell, amount)
    [ @rules.classify(category: category, buy_date: Date.parse(buy), sell_date: Date.parse(sell)), BigDecimal(amount.to_s) ]
  end

  def estimate(gains, slab: 30, exemption: 125_000)
    TaxCenter::Estimate.new(gains: gains, slab_rate: slab, exemption_limit: exemption)
  end

  test "totals by bucket" do
    result = estimate([
      gain("equity", "2024-08-01", "2025-01-01", 10_000),  # STCG equity
      gain("equity", "2022-01-01", "2025-01-01", 50_000),  # LTCG equity
      gain("debt", "2024-01-01", "2025-01-01", 4_000),     # slab
      gain("other_unlisted", "2020-01-01", "2025-01-01", 7_000) # LTCG other
    ])

    assert_equal 10_000, result.totals[:stcg_equity]
    assert_equal 50_000, result.totals[:ltcg_equity]
    assert_equal 4_000, result.totals[:slab]
    assert_equal 7_000, result.totals[:ltcg_other]
  end

  test "exemption covers equity LTCG first and tax applies to the rest" do
    result = estimate([ gain("equity", "2022-01-01", "2025-01-01", 200_000) ])

    assert_equal 125_000, result.exemption_used
    assert_equal 0, result.exemption_remaining
    assert_equal 75_000, result.taxable
    assert_equal BigDecimal("9375"), result.tax # 12.5% of 75,000
  end

  test "exemption remaining when equity LTCG is below the limit" do
    result = estimate([ gain("equity", "2022-01-01", "2025-01-01", 40_000) ], exemption: 100_000)

    assert_equal 40_000, result.exemption_used
    assert_equal 60_000, result.exemption_remaining
    assert_equal 0, result.tax
  end

  test "slab gains use the supplied slab rate" do
    result = estimate([ gain("debt", "2024-01-01", "2025-01-01", 10_000) ], slab: 20)

    assert_equal 2_000, result.tax
  end

  test "short term losses offset short and long term gains" do
    result = estimate([
      gain("equity", "2024-08-01", "2025-01-01", -30_000), # STCL
      gain("equity", "2022-01-01", "2025-01-01", 200_000)  # LTCG
    ])

    assert_equal 125_000, result.exemption_used
    assert_equal 45_000, result.taxable
    assert_equal 0, result.unabsorbed_short_loss
  end

  test "long term losses offset only long term gains" do
    result = estimate([
      gain("equity", "2022-01-01", "2025-01-01", -30_000), # LTCL
      gain("equity", "2024-08-01", "2025-01-01", 50_000)   # STCG at 20%
    ])

    assert_equal 30_000, result.unabsorbed_long_loss
    assert_equal 50_000, result.taxable
    assert_equal 10_000, result.tax
  end

  test "losses are applied against the highest rate gains first" do
    result = estimate([
      gain("equity", "2024-08-01", "2025-01-01", 10_000), # STCG at 20%
      gain("debt", "2024-01-01", "2025-01-01", 10_000),   # slab 30%
      gain("equity", "2023-08-01", "2024-03-01", -5_000)  # STCL at the old 15% rate, its own group
    ])

    # the 5k loss is applied to the 30% slab gain first
    assert_equal 15_000, result.taxable
    assert_equal BigDecimal("3500"), result.tax # 10k @ 20% + 5k @ 30% = 2000 + 1500
  end

  test "exempt gains are tracked but not taxed" do
    result = estimate([ gain("exempt", "2018-01-01", "2026-01-01", 90_000) ])

    assert_equal 90_000, result.totals[:exempt]
    assert_equal 0, result.tax
    assert_equal 0, result.taxable
  end
end
