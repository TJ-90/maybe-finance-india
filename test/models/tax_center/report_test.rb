require "test_helper"

class TaxCenter::ReportTest < ActiveSupport::TestCase
  include TaxTestHelper

  setup do
    @family = inr_family
    @account = create_investment_account(@family)
    @equity = create_tax_security("EQFUND")
    @debt = create_tax_security("DEBTFUND", tax_category: "debt")
  end

  def report(fy_start_year, slab_rate: 30)
    TaxCenter::Report.new(family: @family, accounts: [ @account ], financial_year_start: Date.new(fy_start_year, 4, 1), slab_rate: slab_rate)
  end

  test "only sales inside the financial year are included" do
    create_folio_trade @account, @equity, qty: 100, price: 100, date: Date.new(2022, 1, 10)
    create_folio_trade @account, @equity, qty: -10, price: 150, date: Date.new(2025, 3, 31) # FY 2024-25
    create_folio_trade @account, @equity, qty: -10, price: 160, date: Date.new(2025, 4, 1)  # FY 2025-26

    assert_equal "2024-25", report(2024).label
    assert_equal [ 500 ], report(2024).lines.map(&:gain)
    assert_equal [ 600 ], report(2025).lines.map(&:gain)
  end

  test "totals by bucket and exemption used and remaining" do
    create_folio_trade @account, @equity, qty: 1000, price: 100, date: Date.new(2022, 1, 10)
    create_folio_trade @account, @equity, qty: -400, price: 250, date: Date.new(2025, 6, 1)  # LTCG 60,000
    create_folio_trade @account, @equity, qty: 100, price: 100, date: Date.new(2025, 7, 1)
    create_folio_trade @account, @equity, qty: -100, price: 130, date: Date.new(2025, 9, 1)  # lot from 2022 is first in line
    create_folio_trade @account, @debt, qty: 100, price: 10, date: Date.new(2025, 1, 1)
    create_folio_trade @account, @debt, qty: -100, price: 12, date: Date.new(2025, 8, 1)     # slab 200

    estimate = report(2025).estimate

    assert_equal 60_000 + 3_000, estimate.totals[:ltcg_equity] # second sale also consumes the 2022 lot (long term)
    assert_equal 0, estimate.totals[:stcg_equity]
    assert_equal 200, estimate.totals[:slab]
    assert_equal 63_000, estimate.exemption_used
    assert_equal 62_000, estimate.exemption_remaining
    assert_equal 60, estimate.tax # slab only: 200 * 30%
  end

  test "slab rate input changes the estimate" do
    create_folio_trade @account, @debt, qty: 100, price: 10, date: Date.new(2025, 1, 1)
    create_folio_trade @account, @debt, qty: -100, price: 20, date: Date.new(2025, 8, 1)

    assert_equal 300, report(2025, slab_rate: 30).estimate.tax
    assert_equal 100, report(2025, slab_rate: 10).estimate.tax
  end

  test "redemption rows net a sale across lots with a short and long split" do
    create_folio_trade @account, @equity, qty: 10, price: 100, date: Date.new(2022, 1, 10)
    create_folio_trade @account, @equity, qty: 10, price: 100, date: Date.new(2025, 5, 1)
    create_folio_trade @account, @equity, qty: -20, price: 150, date: Date.new(2025, 8, 1)

    rows = report(2025).redemption_rows

    assert_equal 1, rows.size
    assert_equal 1000, rows.first.gain
    assert_equal 500, rows.first.long_term_gain
    assert_equal 500, rows.first.short_term_gain
  end

  test "the exemption limit follows the financial year" do
    assert_equal 100_000, report(2023).exemption_limit
    assert_equal 125_000, report(2025).exemption_limit
  end

  test "grandfathering warnings are collected for old equity lots" do
    create_folio_trade @account, @equity, qty: 10, price: 100, date: Date.new(2017, 6, 1)
    create_folio_trade @account, @equity, qty: -10, price: 150, date: Date.new(2025, 8, 1)

    result = report(2025)

    assert_equal 1, result.grandfathering_lines.size
    assert_match(/grandfathered cost/, result.warnings.join)
  end

  test "other unlisted losses are labelled in totals" do
    hybrid = create_tax_security("HYBRID", tax_category: "other_unlisted")
    create_folio_trade @account, hybrid, qty: 10, price: 100, date: Date.new(2020, 1, 1)
    create_folio_trade @account, hybrid, qty: -10, price: 80, date: Date.new(2025, 8, 1)

    assert_equal(-200, report(2025).estimate.totals[:ltcg_other])
  end
end
