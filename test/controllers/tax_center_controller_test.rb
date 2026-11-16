require "test_helper"

class TaxCenterControllerTest < ActionDispatch::IntegrationTest
  include TaxTestHelper

  setup do
    travel_to Date.new(2026, 11, 16)
    sign_in @user = users(:family_admin)
    @family = inr_family
    @account = create_investment_account(@family)
    @fund = create_tax_security("TAXFUND")

    create_folio_trade @account, @fund, qty: 1000, price: 100, date: Date.new(2022, 1, 10), folio: "1111"
    create_folio_trade @account, @fund, qty: -100, price: 150, date: Date.new(2026, 6, 1), folio: "1111"
    set_price @fund, 160
  end

  test "page renders every section frame and the disclaimer" do
    get tax_center_path

    assert_response :success
    assert_select "turbo-frame#tax_realized_gains[src]"
    assert_select "turbo-frame#tax_harvesting[src]"
    assert_select "turbo-frame#tax_calculator[src]"
    assert_select "turbo-frame#tax_categories[src]"
    assert_select "[data-testid=tax-disclaimer]", text: /Indicative estimates only\. Surcharge, cess and rebates are not computed\. Consult a tax professional\./
  end

  test "page without investment accounts shows an empty state" do
    @family.accounts.where(accountable_type: "Investment").destroy_all

    get tax_center_path

    assert_response :success
    assert_select "turbo-frame#tax_realized_gains", count: 0
  end

  test "realized gains section shows totals, exemption and the netted table" do
    get realized_gains_tax_center_path

    assert_response :success
    assert_select "#tax-realized-gains", text: /2026-27/
    assert_select "#tax-realized-gains", text: /LTCG \(equity\)/
    assert_select "#tax-realized-gains", text: /Exemption remaining/
    assert_select "#tax-redemptions tbody tr", count: 1
    assert_select "#tax-redemptions", text: /1111/
    assert_select "[data-testid=tax-disclaimer]"
  end

  test "financial year and slab rate come from query params" do
    create_folio_trade @account, @fund, qty: -100, price: 130, date: Date.new(2025, 6, 1), folio: "1111"

    get realized_gains_tax_center_path(fy: 2025, slab: 20)

    assert_response :success
    assert_select "#tax-realized-gains", text: /2025-26/
    assert_select "#tax-realized-gains", text: /slab 20%/
    assert_select "#tax-redemptions tbody tr", count: 1
  end

  test "invalid params fall back to defaults" do
    get realized_gains_tax_center_path(fy: "abc", slab: "not-a-number")

    assert_response :success
    assert_select "#tax-realized-gains", text: /slab 30%/
  end

  test "harvesting section lists LTCG recommendations and loss candidates" do
    loser = create_tax_security("LOSSFUND")
    create_folio_trade @account, loser, qty: 50, price: 300, date: Date.new(2024, 1, 10)
    set_price loser, 200

    get harvesting_tax_center_path

    assert_response :success
    assert_select "#ltcg-harvest tbody tr", count: 1
    assert_select "#ltcg-harvest", text: /TAXFUND Fund/
    assert_select "#loss-harvest tbody tr", count: 1
    assert_select "#loss-harvest", text: /LTCL/
  end

  test "harvesting only uses the selected accounts" do
    other = create_investment_account(@family, name: "Spouse demat")
    create_folio_trade other, @fund, qty: 100, price: 100, date: Date.new(2023, 1, 10)

    get harvesting_tax_center_path(account_ids: [ @account.id ])

    assert_response :success
    assert_select "#ltcg-harvest tbody tr", count: 1
    assert_select "#ltcg-harvest", text: /Spouse demat/, count: 0
  end

  test "calculator renders the form and a result with FIFO details" do
    get calculator_tax_center_path
    assert_response :success
    assert_select "#tax-calculator form"
    assert_select "#calculator-result", count: 0

    holding = "#{@account.id}|#{@fund.id}|1111"
    get calculator_tax_center_path(holding: holding, units: "100", sale_date: "2026-11-16", price: "200")

    assert_response :success
    assert_select "#calculator-result"
    assert_select "#calculator-result details summary", text: /View FIFO details/
    assert_select "#calculator-lots tbody tr", count: 1
    assert_select "#calculator-tax"
  end

  test "calculator labels the override holding period option as a planning view" do
    holding = "#{@account.id}|#{@fund.id}|1111"

    get calculator_tax_center_path(holding: holding, units: "10", price: "200", only_held_over_months: "6")

    assert_response :success
    assert_select "#tax-calculator", text: /Planning view/
  end

  test "calculator ignores a holding the family does not have" do
    get calculator_tax_center_path(holding: "0|0|", units: "10", price: "200")

    assert_response :success
    assert_select "#calculator-result", count: 0
  end

  test "category mapping lists held securities" do
    get categories_tax_center_path

    assert_response :success
    assert_select "#tax-categories", text: /TAXFUND Fund/
    assert_select "#tax-categories form", minimum: 1
  end

  test "category mapping writes a family override" do
    assert_difference -> { FamilySecurityOverride.count }, 1 do
      patch update_category_tax_center_path(security_id: @fund.id), params: { tax_category: "other_unlisted", asset_class: "hybrid" }
    end

    assert_redirected_to(/tax_center\/categories\?.*fy=2026/)
    override = FamilySecurityOverride.find_by!(family: @family, security: @fund)
    assert_equal "other_unlisted", override.tax_category
    assert_equal "hybrid", override.asset_class
    assert_equal "equity", @fund.reload.tax_category # the security itself is untouched
  end

  test "category mapping removes an override when cleared and rejects invalid values" do
    FamilySecurityOverride.create!(family: @family, security: @fund, tax_category: "debt")

    assert_difference -> { FamilySecurityOverride.count }, -1 do
      patch update_category_tax_center_path(security_id: @fund.id), params: { tax_category: "", asset_class: "" }
    end

    assert_no_difference -> { FamilySecurityOverride.count } do
      patch update_category_tax_center_path(security_id: @fund.id), params: { tax_category: "bogus" }
    end
    assert_redirected_to(/categories/)
  end

  test "category mapping cannot touch securities the family has not traded" do
    stranger = create_tax_security("STRANGER")

    patch update_category_tax_center_path(security_id: stranger.id), params: { tax_category: "debt" }

    assert_response :not_found
  end

  test "an override changes the tax classification" do
    FamilySecurityOverride.create!(family: @family, security: @fund, tax_category: "debt")
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2025, 1, 1), folio: "2222"
    create_folio_trade @account, @fund, qty: -10, price: 110, date: Date.new(2026, 7, 1), folio: "2222" # bought after 2023-04-01

    get realized_gains_tax_center_path

    assert_response :success
    assert_select "#tax-realized-gains", text: /Taxed at slab rate/
    assert_select "#tax-realized-gains", text: /50AA/
  end

  test "exports realized gains as csv" do
    get export_tax_center_path(kind: "realized")

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
    rows = CSV.parse(response.body)
    assert_equal "Financial year", rows.first.first
    assert_equal 2, rows.size
    assert_equal "1111", rows.second[3]
    assert_equal "5000.00", rows.second[8]
  end

  test "exports harvesting recommendations as csv" do
    get export_tax_center_path(kind: "harvesting")

    assert_response :success
    rows = CSV.parse(response.body)
    assert_equal "Type", rows.first.first
    assert_equal "LTCG harvest", rows.second.first
  end

  test "requires authentication" do
    reset!

    get tax_center_path

    assert_redirected_to new_session_path
  end

  test "navigation includes the Tax item" do
    get root_path

    assert_select "a[href=?]", tax_center_path, text: /Tax/
  end
end
