require "test_helper"

class FamilyTest < ActiveSupport::TestCase
  include SyncableInterfaceTest

  def setup
    @syncable = families(:dylan_family)
  end

  test "new families default to India settings" do
    family = Family.create!(name: "Sharma")

    assert_equal "INR", family.currency
    assert_equal "IN", family.country
    assert_equal "%d-%m-%Y", family.date_format
    assert_equal "Asia/Kolkata", family.timezone
  end
end
