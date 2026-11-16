require "test_helper"

class Family::PlaidConnectableTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "can connect plaid us when configured outside India" do
    Provider::Registry.stubs(:plaid_provider_for_region).with(:us).returns(mock)
    assert @family.can_connect_plaid_us?
  end

  test "cannot connect plaid when not configured" do
    Provider::Registry.stubs(:plaid_provider_for_region).returns(nil)
    assert_not @family.can_connect_plaid_us?
    assert_not @family.can_connect_plaid_eu?
  end

  test "cannot connect plaid for Indian families even when configured" do
    @family.update!(country: "IN")
    Provider::Registry.stubs(:plaid_provider_for_region).returns(mock)

    assert_not @family.can_connect_plaid_us?
    assert_not @family.can_connect_plaid_eu?
  end
end
