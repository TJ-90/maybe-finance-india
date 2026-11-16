require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "product_name comes from config" do
    assert_equal Rails.application.config.x.product_name, product_name
    assert_equal "Kosh", product_name
  end

  test "format_money_compact formats INR compactly" do
    assert_equal "₹12.35 L", format_money_compact(Money.new(1234567, "INR"))
    assert_equal "₹1.20 Cr", format_money_compact(Money.new(12000000, "INR"))
    assert_equal "$45.6K", format_money_compact(Money.new(45600, "USD"))
    assert_nil format_money_compact(nil)
  end

  test "stripe and intercom are hidden unless configured" do
    with_env_overrides STRIPE_SECRET_KEY: nil, STRIPE_WEBHOOK_SECRET: nil, INTERCOM_APP_ID: nil, INTERCOM_IDENTITY_VERIFICATION_KEY: nil do
      assert_not stripe_configured?
      assert_not intercom_configured?
    end

    with_env_overrides STRIPE_SECRET_KEY: "sk", STRIPE_WEBHOOK_SECRET: "whsec", INTERCOM_APP_ID: "app", INTERCOM_IDENTITY_VERIFICATION_KEY: "key" do
      assert stripe_configured?
      assert intercom_configured?
    end
  end
end
