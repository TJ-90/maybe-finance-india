require "test_helper"

class Assistant::Function::GetTaxSummaryTest < ActiveSupport::TestCase
  include TaxTestHelper

  setup do
    @family = inr_family
    @user = users(:family_admin)
    @account = create_investment_account(@family)
    @equity = create_tax_security("EQFUND")
  end

  test "summarises realized gains and the remaining exemption for a financial year" do
    create_folio_trade @account, @equity, qty: 1000, price: 100, date: Date.new(2022, 1, 10)
    create_folio_trade @account, @equity, qty: -400, price: 250, date: Date.new(2025, 6, 1) # LTCG 60,000

    result = Assistant::Function::GetTaxSummary.new(@user).call("financial_year_start" => "2025-08-01")

    assert_equal "2025-26", result[:financial_year]
    assert_equal Money.new(60_000, "INR").format, result[:realized_gains][:equity_long_term]
    assert_equal Money.new(60_000, "INR").format, result[:ltcg_equity_exemption][:used]
    assert_equal Money.new(65_000, "INR").format, result[:ltcg_equity_exemption][:remaining]
    assert_equal 1, result[:sales_count]
    assert_includes result[:disclaimer], "not tax advice"
  end

  test "defaults to the current financial year and tolerates a bad date" do
    function = Assistant::Function::GetTaxSummary.new(@user)
    current = Period.financial_year_label(Date.current)

    assert_equal current, function.call("financial_year_start" => nil)[:financial_year]
    assert_equal current, function.call("financial_year_start" => "garbage")[:financial_year]
    assert_equal current, function.call({})[:financial_year]
  end

  test "schema requires the financial year parameter for strict mode" do
    schema = Assistant::Function::GetTaxSummary.new(@user).params_schema

    assert_equal [ "financial_year_start" ], schema[:required]
  end
end
