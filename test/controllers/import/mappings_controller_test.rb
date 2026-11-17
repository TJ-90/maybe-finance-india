require "test_helper"

class Import::MappingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)

    @import = imports(:transaction)
  end

  test "updates mapping" do
    mapping = import_mappings(:one)
    new_category = categories(:income)

    patch import_mapping_path(@import, mapping), params: {
      import_mapping: {
        mappable_type: "Category",
        mappable_id: new_category.id,
        key: "Food"
      }
    }

    mapping.reload

    assert_equal new_category, mapping.mappable
    assert_equal "Food", mapping.key

    assert_redirected_to import_confirm_path(@import)
  end

  test "owner step stores a member, joint, or creates a new person with the residency choice" do
    family = @user.family
    import = family.imports.create!(type: "TradeImport")
    mapping = import.mappings.create!(type: "Import::AccountMapping", key: "Trading", create_when_empty: true)
    member = family.household_members.create!(name: "Rahul", relationship: "self", residency_status: "nri")

    patch owner_import_mapping_path(import, mapping), params: { household_member_id: member.id }
    assert_equal member.id, mapping.reload.value
    assert_equal member, mapping.owner

    patch owner_import_mapping_path(import, mapping), params: { household_member_id: "joint" }
    assert_nil mapping.reload.owner

    assert_difference "family.household_members.count", 1 do
      patch owner_import_mapping_path(import, mapping), params: { new_member: { name: "Asha", relationship: "spouse", residency_status: "resident" } }
    end
    assert_equal "Asha", mapping.reload.owner.name

    assert_no_difference "family.household_members.count" do
      patch owner_import_mapping_path(import, mapping), params: { new_member: { name: "Bad", relationship: "other" } }
    end
  end

  test "an account select change does not clear the chosen owner" do
    family = @user.family
    import = family.imports.create!(type: "TradeImport")
    mapping = import.mappings.create!(type: "Import::AccountMapping", key: "Trading", create_when_empty: true, value: "joint")

    patch import_mapping_path(import, mapping), params: { import_mapping: { type: "Import::AccountMapping", key: "Trading", mappable_type: "Account", mappable_id: Import::Mapping::CREATE_NEW_KEY } }

    assert_equal "joint", mapping.reload.value
  end

  test "new accounts from a trade import are investment accounts owned by the chosen member" do
    family = @user.family
    member = family.household_members.create!(name: "Rahul", relationship: "self", residency_status: "nri")
    import = family.imports.create!(type: "TradeImport")
    mapping = import.mappings.create!(type: "Import::AccountMapping", key: "Trading", create_when_empty: true, value: member.id)

    mapping.create_mappable!

    account = family.accounts.find_by!(name: "Trading")
    assert_equal "Investment", account.accountable_type
    assert_equal member, account.household_member
  end
end
