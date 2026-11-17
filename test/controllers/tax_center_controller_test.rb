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

  # --- household members and residency ---

  def household
    @nri = @family.household_members.create!(name: "Rahul", relationship: "self", residency_status: "nri")
    @resident = @family.household_members.create!(name: "Asha", relationship: "spouse", residency_status: "resident", slab_rate: 20)
    @account.update!(household_member: @nri)
    @asha_account = create_investment_account(@family, name: "Asha demat")
    @asha_account.update!(household_member: @resident)
    create_folio_trade @asha_account, @fund, qty: 50, price: 100, date: Date.new(2023, 1, 10)
    create_folio_trade @asha_account, @fund, qty: -50, price: 200, date: Date.new(2026, 8, 1)
  end

  test "without household members the account checkboxes and a setup prompt are shown" do
    get tax_center_path

    assert_select "[data-testid=household-prompt]"
    assert_select "select#member_id", count: 0
    assert_select "input[name='account_ids[]']", minimum: 1
    assert_select "#tax-filters details[open]"
  end

  test "the member select replaces the account checkboxes and keeps an advanced disclosure" do
    household

    get tax_center_path

    assert_select "[data-testid=household-prompt]", count: 0
    assert_select "select#member_id option", count: 2
    assert_select "select#member_id option[selected]", text: /Rahul \(NRI\)/
    assert_select "#tax-filters details summary", text: /Advanced: choose accounts/
    assert_select "#tax-filters details[open]", count: 0
    assert_select "[data-testid=residency-notes]", text: /NRI/
    assert_select "turbo-frame#tax_interest[src]"
  end

  test "a member's report only uses their own accounts and the NRI sees estimated TDS" do
    household

    get realized_gains_tax_center_path(member_id: @nri.id)

    assert_response :success
    assert_select "#tax-redemptions tbody tr", count: 1
    assert_select "#realized-tds-total"
    assert_select "#tax-redemptions th", text: /Est\. TDS/
    assert_select "[data-testid=nri-tds-estimate-note]", text: /estimate/

    get realized_gains_tax_center_path(member_id: @resident.id)

    assert_select "#tax-redemptions tbody tr", count: 1
    assert_select "#realized-tds-total", count: 0
    assert_select "#tax-redemptions th", text: /Est\. TDS/, count: 0
  end

  test "advanced account choice overrides the member's accounts" do
    household

    get realized_gains_tax_center_path(member_id: @nri.id, account_ids: [ @asha_account.id ])

    assert_select "#tax-redemptions tbody tr", count: 1
    assert_select "#tax-redemptions", text: /Asha demat|TAXFUND/
  end

  test "an unknown member falls back to you and the slab rate follows the member" do
    household

    get realized_gains_tax_center_path(member_id: "nope")
    assert_select "#tax-realized-gains", text: /slab 30%/

    get realized_gains_tax_center_path(member_id: @resident.id)
    assert_select "#tax-realized-gains", text: /slab 20%/

    get realized_gains_tax_center_path(member_id: @resident.id, slab: 25)
    assert_select "#tax-realized-gains", text: /slab 25%/
  end

  test "harvesting and the calculator show the NRI TDS estimate" do
    household

    get harvesting_tax_center_path(member_id: @nri.id)
    assert_select "#ltcg-harvest th", text: /Est\. TDS/

    get calculator_tax_center_path(member_id: @nri.id, holding: "#{@account.id}|#{@fund.id}|1111", units: "100", sale_date: "2026-11-16", price: "200")
    assert_select "#calculator-tds-amount"

    get calculator_tax_center_path(member_id: @resident.id)
    assert_select "[data-testid=calculator-tds]", count: 0
  end

  test "interest income section lists NRE as exempt and NRO as taxable for an NRI" do
    household
    nre = @family.accounts.create!(name: "NRE", balance: 0, currency: "INR", accountable: Depository.new, subtype: "nre", household_member: @nri)
    nro = @family.accounts.create!(name: "NRO", balance: 0, currency: "INR", accountable: Depository.new, subtype: "nro", household_member: @nri)
    nre.entries.create!(name: "Interest credit", date: Date.new(2026, 6, 30), amount: -5000, currency: "INR", entryable: Transaction.new(kind: "standard"))
    nro.entries.create!(name: "Interest credit", date: Date.new(2026, 6, 30), amount: -3000, currency: "INR", entryable: Transaction.new(kind: "standard"))

    get interest_tax_center_path(member_id: @nri.id)

    assert_response :success
    assert_select "#interest-exempt", text: /5,000/
    assert_select "#interest-taxable", text: /3,000/
    assert_select "#interest-rows", text: /NRO interest is taxable/
  end

  test "export adds the TDS column for an NRI" do
    household

    get export_tax_center_path(member_id: @nri.id, kind: "realized")

    assert_response :success
    assert_match(/Estimated TDS \(NRI\)/, response.body)
  end
end
