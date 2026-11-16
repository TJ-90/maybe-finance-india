require "test_helper"

class AccountTest < ActiveSupport::TestCase
  include SyncableInterfaceTest, EntriesTestHelper

  setup do
    @account = @syncable = accounts(:depository)
    @family = families(:dylan_family)
  end

  test "can destroy" do
    assert_difference "Account.count", -1 do
      @account.destroy
    end
  end

  test "gets short/long subtype label" do
    account = @family.accounts.create!(
      name: "Test Investment",
      balance: 1000,
      currency: "USD",
      subtype: "nps_tier1",
      accountable: Investment.new
    )

    assert_equal "NPS Tier I", account.short_subtype_label
    assert_equal "NPS Tier I", account.long_subtype_label

    # Test with nil subtype
    account.update!(subtype: nil)
    assert_equal "Investments", account.short_subtype_label
    assert_equal "Investments", account.long_subtype_label
  end

  test "gets Indian subtype labels for each accountable" do
    assert_equal "NRE", Depository.short_subtype_label_for("nre")
    assert_equal "Salary Account", Depository.long_subtype_label_for("salary")
    assert_equal "Demat Account", Investment.long_subtype_label_for("demat")
    assert_equal "PMS/AIF", Investment.short_subtype_label_for("pms_aif")
    assert_equal "Home Loan", Loan.long_subtype_label_for("home")
    assert_equal "Plot / Land", Property.long_subtype_label_for("plot")
    assert_nil Investment.long_subtype_label_for("401k")
  end
end
