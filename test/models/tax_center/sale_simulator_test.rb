require "test_helper"

class TaxCenter::SaleSimulatorTest < ActiveSupport::TestCase
  include TaxTestHelper

  setup do
    @family = inr_family
    @account = create_investment_account(@family)
    @fund = create_tax_security("SIMFUND")
    create_folio_trade @account, @fund, qty: 100, price: 100, date: Date.new(2022, 1, 10) # long term
    create_folio_trade @account, @fund, qty: 100, price: 120, date: Date.new(2026, 1, 10) # short term on 2026-06-01
    @lots = Holding::TaxLots.new([ @account ], currency: "INR").open_lots
  end

  def simulate(units:, **options)
    TaxCenter::SaleSimulator.new(family: @family, lots: @lots, units: units, sale_date: Date.new(2026, 6, 1),
                                 price: 200, **options)
  end

  test "lots are consumed first in first out with a gain type per lot" do
    result = simulate(units: 150)

    assert_equal [ 100, 50 ], result.lines.map(&:qty)
    assert_equal [ :long, :short ], result.lines.map(&:term)
    assert_equal [ 10_000, 4_000 ], result.lines.map(&:gain)
    assert_equal 0, result.shortfall
  end

  test "estimated tax uses the exemption and the short term rate" do
    result = simulate(units: 150)

    # LTCG 10,000 sits inside the 1.25 lakh exemption; STCG 4,000 at 20%
    assert_equal 10_000, result.estimate.exemption_used
    assert_equal 800, result.incremental_tax
  end

  test "gains already realized this year use up the exemption" do
    result = simulate(units: 100, realized_ltcg: 120_000)

    # 10,000 + 120,000 = 130,000; 5,000 over the 1.25 lakh exemption taxed at 12.5%
    assert_equal BigDecimal("625"), result.incremental_tax
  end

  test "overriding the holding period skips lots held for that many months or less" do
    result = simulate(units: 50, only_held_over_months: 12)

    assert_equal [ 50 ], result.lines.map(&:qty)
    assert_equal [ Date.new(2022, 1, 10) ], result.lines.map(&:buy_date)
    assert_equal 1, result.skipped_lots.size
  end

  test "asking for more units than are held reports the shortfall" do
    result = simulate(units: 250)

    assert_equal 200, result.units
    assert_equal 50, result.shortfall
  end
end
