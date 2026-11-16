require "test_helper"

class TaxCenter::HarvesterTest < ActiveSupport::TestCase
  include TaxTestHelper

  setup do
    travel_to Date.new(2026, 11, 16) # FY 2026-27: exemption 1,25,000
    @family = inr_family
    @account = create_investment_account(@family)
    @fund = create_tax_security("HARVEST")
  end

  def harvester
    report = TaxCenter::Report.new(family: @family, accounts: [ @account ], financial_year_start: Period.financial_year_start(Date.current))
    TaxCenter::Harvester.new(family: @family, report: report)
  end

  test "recommended LTCG never exceeds the remaining exemption and lands within one rupee" do
    create_folio_trade @account, @fund, qty: 5000, price: 100, date: Date.new(2024, 1, 10)
    set_price @fund, BigDecimal("133.33") # 33.33 gain per unit, 1,66,650 available

    result = harvester

    assert_equal 125_000, result.exemption_remaining
    assert_equal 1, result.ltcg_recommendations.size
    recommended = result.recommended_ltcg
    assert recommended <= 125_000, "recommended #{recommended} exceeds the exemption"
    assert_operator 125_000 - recommended, :<, 1
    assert_equal BigDecimal("3750.375"), result.ltcg_recommendations.first.units # floored to 3 decimals
  end

  test "everything long term is recommended when it fits within the exemption" do
    create_folio_trade @account, @fund, qty: 100, price: 100, date: Date.new(2024, 1, 10)
    set_price @fund, 150

    rec = harvester.ltcg_recommendations.first

    assert_equal 100, rec.units
    assert_equal 5_000, rec.gain
    assert_equal 15_000, rec.proceeds
  end

  test "gains realized earlier this year reduce what is left to harvest" do
    create_folio_trade @account, @fund, qty: 3000, price: 100, date: Date.new(2020, 1, 10)
    create_folio_trade @account, @fund, qty: -500, price: 150, date: Date.new(2026, 5, 1) # 25,000 LTCG realized
    set_price @fund, 150

    result = harvester

    assert_equal 100_000, result.exemption_remaining
    assert_equal 100_000, result.recommended_ltcg # 2,500 units left, 2,000 of them fill the exemption
    assert_equal 2000, result.ltcg_recommendations.first.units
  end

  test "FIFO is binding: a lot in front that is not long term with a gain blocks the lots behind it" do
    create_folio_trade @account, @fund, qty: 100, price: 200, date: Date.new(2023, 1, 10) # loss lot first
    create_folio_trade @account, @fund, qty: 100, price: 100, date: Date.new(2024, 1, 10) # gain lot behind it
    set_price @fund, 150

    assert_empty harvester.ltcg_recommendations
  end

  test "short term lots are never part of the LTCG harvest" do
    create_folio_trade @account, @fund, qty: 100, price: 100, date: Date.new(2026, 8, 1)
    set_price @fund, 150

    assert_empty harvester.ltcg_recommendations
  end

  test "folios of one scheme are harvested separately and together stay within the exemption" do
    create_folio_trade @account, @fund, qty: 2000, price: 100, date: Date.new(2024, 1, 10), folio: "1111" # 100,000 gain at 150
    create_folio_trade @account, @fund, qty: 2000, price: 100, date: Date.new(2024, 2, 10), folio: "2222"
    set_price @fund, 150

    result = harvester

    assert_equal %w[1111 2222], result.ltcg_recommendations.map(&:folio).sort
    assert_equal 125_000, result.recommended_ltcg
    assert_equal [ 500, 2000 ], result.ltcg_recommendations.map(&:units).sort
  end

  test "stocks are harvested in whole units" do
    stock = create_tax_security("STOCKCO", kind: "stock")
    create_folio_trade @account, stock, qty: 1000, price: 100, date: Date.new(2024, 1, 10)
    set_price stock, 233 # 133 per unit: 125000 / 133 = 939.8

    rec = harvester.ltcg_recommendations.first

    assert_equal 939, rec.units
    assert rec.gain <= 125_000
  end

  test "non equity lots are not harvested for the exemption" do
    hybrid = create_tax_security("HYBRIDX", tax_category: "other_unlisted")
    create_folio_trade @account, hybrid, qty: 100, price: 100, date: Date.new(2020, 1, 10)
    set_price hybrid, 150

    assert_empty harvester.ltcg_recommendations
  end

  test "securities without a price are skipped" do
    create_folio_trade @account, @fund, qty: 100, price: 100, date: Date.new(2024, 1, 10)

    assert_empty harvester.ltcg_recommendations
  end

  test "loss harvesting labels short and long term losses" do
    create_folio_trade @account, @fund, qty: 100, price: 200, date: Date.new(2024, 1, 10)
    short_fund = create_tax_security("SHORTLOSS")
    create_folio_trade @account, short_fund, qty: 100, price: 200, date: Date.new(2026, 8, 1)
    set_price @fund, 150
    set_price short_fund, 150

    rows = harvester.loss_rows.index_by { |row| row.security.ticker }

    assert_equal "LTCL", rows["HARVEST"].label
    assert_equal(-5_000, rows["HARVEST"].net)
    assert_equal "STCL", rows["SHORTLOSS"].label
  end

  test "loss harvesting respects FIFO by netting the prefix that has to be sold first" do
    create_folio_trade @account, @fund, qty: 100, price: 100, date: Date.new(2024, 1, 10) # gain 5,000 at 150
    create_folio_trade @account, @fund, qty: 100, price: 300, date: Date.new(2024, 3, 10) # loss 15,000
    set_price @fund, 150

    row = harvester.loss_rows.first

    assert_equal 200, row.units # the gain lot has to go first
    assert_equal(-10_000, row.net)
  end

  test "a loss row only offsets gains it is allowed to offset" do
    create_folio_trade @account, @fund, qty: 100, price: 200, date: Date.new(2024, 1, 10)
    set_price @fund, 150

    assert_not harvester.loss_rows.first.offsets_gains # no realized gains yet

    other = create_tax_security("GAINER")
    create_folio_trade @account, other, qty: 10, price: 100, date: Date.new(2024, 1, 10)
    create_folio_trade @account, other, qty: -10, price: 200, date: Date.new(2026, 6, 1)

    assert harvester.loss_rows.find { |r| r.security == @fund }.offsets_gains
  end
end
