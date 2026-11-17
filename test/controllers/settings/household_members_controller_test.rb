require "test_helper"

class Settings::HouseholdMembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
  end

  test "index shows members and the empty state" do
    get settings_household_members_path
    assert_response :success
    assert_select "p", text: /No household members yet/

    @family.household_members.create!(name: "Rahul", relationship: "self", residency_status: "nri")
    get settings_household_members_path
    assert_select "#settings-nav, p", text: /Rahul/
  end

  test "the form offers Resident and NRI as unchecked required radios" do
    get new_settings_household_member_path

    assert_response :success
    assert_select "input[type=radio][name='household_member[residency_status]'][required]", count: 2
    assert_select "input[type=radio][name='household_member[residency_status]'][checked]", count: 0
    assert_select "[data-testid=residency-field]", text: /TDS estimate/
  end

  test "create requires a residency choice" do
    assert_no_difference "HouseholdMember.count" do
      post settings_household_members_path, params: { household_member: { name: "Rahul", relationship: "self" } }
    end

    assert_response :unprocessable_entity
  end

  test "create saves the member and can link the login" do
    assert_difference "@family.household_members.count", 1 do
      post settings_household_members_path, params: {
        household_member: { name: "Rahul Sharma", relationship: "self", residency_status: "nri", tax_regime: "new" },
        link_current_user: "1"
      }
    end

    assert_redirected_to settings_household_members_path
    member = @family.household_members.last
    assert_equal BigDecimal("30"), member.slab_rate
    assert_equal member, @user.reload.household_member
  end

  test "update and destroy" do
    member = @family.household_members.create!(name: "Asha", relationship: "spouse", residency_status: "resident")
    account = @family.accounts.create!(name: "Savings", balance: 0, currency: "INR", accountable: Depository.new, household_member: member)

    patch settings_household_member_path(member), params: { household_member: { residency_status: "nri" } }
    assert_equal "nri", member.reload.residency_status

    delete settings_household_member_path(member)
    assert_nil account.reload.household_member_id
  end

  test "other families' members cannot be edited" do
    other = families(:empty).household_members.create!(name: "X", relationship: "self", residency_status: "resident")

    get edit_settings_household_member_path(other)
    assert_response :not_found
  end

  test "account form has a Belongs to select and ignores another family's member" do
    member = @family.household_members.create!(name: "Rahul", relationship: "self", residency_status: "nri")
    other = families(:empty).household_members.create!(name: "X", relationship: "self", residency_status: "resident")

    get new_depository_path
    assert_select "select[name='account[household_member_id]'] option", text: /Rahul \(NRI\)/
    assert_select "[data-testid=nre-nro-hint]"

    post depositories_path, params: { account: { name: "NRE", balance: 10, currency: "INR", subtype: "nre", accountable_type: "Depository", household_member_id: member.id } }
    assert_equal member, @family.accounts.find_by!(name: "NRE").household_member

    post depositories_path, params: { account: { name: "Odd", balance: 10, currency: "INR", accountable_type: "Depository", household_member_id: other.id } }
    assert_nil @family.accounts.find_by!(name: "Odd").household_member_id
  end
end
