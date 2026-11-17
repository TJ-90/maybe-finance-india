require "test_helper"

class TaxCenter::ResidencyTest < ActiveSupport::TestCase
  include TaxTestHelper

  setup do
    @family = inr_family
    @account = create_investment_account(@family)
    @equity = create_tax_security("EQFUND")
    @debt = create_tax_security("DEBTFUND", tax_category: "debt")
    @nri = @family.household_members.create!(name: "Rahul", relationship: "self", residency_status: "nri")
    @resident = @family.household_members.create!(name: "Asha", relationship: "spouse", residency_status: "resident", slab_rate: 20)
  end

  def report(member, year: 2026)
    TaxCenter::Report.new(
      family: @family, accounts: [ @account ], financial_year_start: Date.new(year, 4, 1),
      residency: TaxCenter::Residency.new(member: member)
    )
  end

  test "capital gains rates and the exemption are the same for residents and NRIs" do
    create_folio_trade @account, @equity, qty: 1000, price: 100, date: Date.new(2022, 1, 10)
    create_folio_trade @account, @equity, qty: -400, price: 250, date: Date.new(2026, 6, 1)

    nri = report(@nri).estimate
    resident = report(@resident).estimate

    assert_equal resident.totals, nri.totals
    assert_equal resident.exemption_limit, nri.exemption_limit
    assert_equal BigDecimal("125000"), nri.exemption_limit
    assert_equal resident.tax, nri.tax
  end

  test "an NRI gets an estimated TDS per sale with cess, a resident gets none" do
    create_folio_trade @account, @equity, qty: 100, price: 100, date: Date.new(2022, 1, 10)
    create_folio_trade @account, @equity, qty: -100, price: 250, date: Date.new(2026, 6, 1) # LTCG 15,000

    row = report(@nri).redemption_rows.first

    assert_equal BigDecimal("1950"), row.tds # 12.5% plus 4% cess
    assert_equal BigDecimal("1950"), report(@nri).tds_total
    assert_equal 0, report(@resident).tds_total
    assert_equal 0, report(nil).tds_total
  end

  test "equity short term, specified debt fund and other gains use their own TDS rates" do
    create_folio_trade @account, @equity, qty: 100, price: 100, date: Date.new(2026, 1, 10)
    create_folio_trade @account, @equity, qty: -100, price: 200, date: Date.new(2026, 6, 1)  # STCG 10,000 at 20%
    create_folio_trade @account, @debt, qty: 100, price: 100, date: Date.new(2024, 1, 10)
    create_folio_trade @account, @debt, qty: -100, price: 200, date: Date.new(2026, 7, 1)    # slab, TDS 30%

    tds = report(@nri).redemption_rows.to_h { |row| [ row.redemption.security.ticker, row.tds ] }

    assert_equal BigDecimal("2080"), tds["EQFUND"]
    assert_equal BigDecimal("3120"), tds["DEBTFUND"]
  end

  test "TDS is never charged on a loss" do
    create_folio_trade @account, @equity, qty: 100, price: 300, date: Date.new(2022, 1, 10)
    create_folio_trade @account, @equity, qty: -100, price: 200, date: Date.new(2026, 6, 1)

    assert_equal 0, report(@nri).tds_total
  end

  test "rates are read from config and change on the 2024-07-23 sale date" do
    residency = TaxCenter::Residency.new(member: @nri)
    line = Struct.new(:classification, :gain)
    rules = TaxCenter::Rules.current
    classification = rules.classify(category: "equity", buy_date: Date.new(2020, 1, 1), sell_date: Date.new(2024, 7, 22))

    assert_equal BigDecimal("10.4"), residency.tds_for_lines([ line.new(classification, 100) ], Date.new(2024, 7, 22))
    assert_equal BigDecimal("12.5"), rules.nri_tds_rates(Date.new(2024, 7, 23))[:equity_ltcg]
    assert_equal BigDecimal("10"), rules.nri_tds_rates(Date.new(2024, 7, 22))[:equity_ltcg]
  end

  test "default slab rate and notes come from the config" do
    assert_equal BigDecimal("30"), @nri.tax_slab_rate
    assert_equal BigDecimal("20"), @resident.tax_slab_rate
    assert_nil TaxCenter::Rules.current.default_slab_rate("resident")
    assert TaxCenter::Residency.new(member: @resident).notes.any? { |note| note.include?("basic exemption") }
    assert TaxCenter::Residency.new(member: @nri).notes.any? { |note| note.include?("TDS") }
    assert_empty TaxCenter::Residency.new.notes
  end

  test "the residency section of the config is flagged for verification" do
    yaml = File.read(TaxCenter::Rules::CONFIG_PATH)

    assert_match(/VERIFY: whether the AMC \/ broker lets the Rs 1.25 lakh/, yaml)
    assert_equal false, TaxCenter::Rules.current.nri_tds_considers_ltcg_exemption?
  end

  test "the calculator estimates TDS for an NRI's planned sale" do
    create_folio_trade @account, @equity, qty: 100, price: 100, date: Date.new(2022, 1, 10)
    set_price @equity, 250
    lots = Holding::TaxLots.new([ @account ], currency: "INR").open_lots

    sim = TaxCenter::SaleSimulator.new(
      family: @family, lots: lots, units: 100, sale_date: Date.new(2026, 11, 16), price: 250,
      residency: TaxCenter::Residency.new(member: @nri)
    )

    assert_equal BigDecimal("1950"), sim.tds
  end
end
