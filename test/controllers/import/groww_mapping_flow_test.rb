require "test_helper"
require "support/mutual_fund_scheme_test_helper"
require "support/xlsx_test_helper"

class Import::GrowwMappingFlowTest < ActionDispatch::IntegrationTest
  include MutualFundSchemeTestHelper
  include XlsxTestHelper

  setup do
    @schemes = create_sigma_schemes
    sign_in @user = users(:family_admin)
    @family = @user.family
    @account = @family.accounts.create!(name: "Groww", balance: 0, currency: "INR", accountable: Investment.new, subtype: "mutual_fund")
    @import = @family.imports.create!(type: "BrokerTradebookImport", account: @account)

    xlsx = groww_orders_xlsx([
      [ "Sigma Alpha Index Fund Direct Growth", "PURCHASE", "10", "100", "1,000", "10 Jan 2025" ],
      [ "Zeta Mystery Fund Direct Growth", "PURCHASE", "5", "100", "500", "03 Feb 2025" ]
    ])
    patch import_upload_url(@import), params: { import: { csv_file: xlsx_upload(xlsx), col_sep: ",", account_id: @account.id } }
    patch import_configuration_url(@import), params: { import: { broker_preset: "groww_mf_orders", date_format: "%d %b %Y", number_format: "1,234.56" } }
  end

  test "the map step lists funds, preselects clear matches and flags the rest" do
    get import_confirm_url(@import)

    assert_response :success
    assert_select "h1", text: "Match your funds"
    assert_select "option[selected]", text: /Sigma Alpha Index Fund - Direct Plan - Growth Option \(400001\)/
    assert_match "No clear match in the AMFI list", response.body
    assert_not @import.reload.publishable?
  end

  test "searching offers funds from the whole list" do
    mapping = @import.mappings.schemes.find_by!(key: "Zeta Mystery Fund Direct Growth")

    get import_confirm_url(@import), params: { scheme_q: { mapping.id => "Midcap" } }

    assert_select "option", text: /Sigma Midcap Fund - Direct Plan - Growth Option \(400005\)/
  end

  test "choosing a fund for an unresolved name makes the import publishable" do
    mapping = @import.mappings.schemes.find_by!(key: "Zeta Mystery Fund Direct Growth")
    scheme = @schemes[:midcap_direct]

    patch import_mapping_url(@import, mapping), params: {
      import_mapping: { mappable_type: "MutualFundScheme", mappable_id: scheme.id, key: mapping.key, type: "Import::SchemeMapping" }
    }

    assert_equal scheme, mapping.reload.mappable
    assert @import.reload.publishable?
  end
end
