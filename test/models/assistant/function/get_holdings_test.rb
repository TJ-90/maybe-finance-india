require "test_helper"

class Assistant::Function::GetHoldingsTest < ActiveSupport::TestCase
  include TaxTestHelper

  setup do
    @family = inr_family
    @user = users(:family_admin)
    @family.accounts.where(accountable_type: "Investment").destroy_all # only the demat account below counts
    @account = create_investment_account(@family)
    @security = create_tax_security("FLEXI")
  end

  test "reports holdings with invested amount, gain and xirr" do
    create_folio_trade @account, @security, qty: 100, price: 100, date: 1.year.ago.to_date
    @account.holdings.create!(security: @security, date: Date.current, qty: 100, price: 120, amount: 12_000, currency: "INR")

    result = Assistant::Function::GetHoldings.new(@user).call
    account = result[:accounts].find { |a| a[:name] == "Demat" }
    holding = account[:holdings].first

    assert_equal "INR", result[:currency]
    assert_equal "FLEXI", holding[:ticker]
    assert_equal 100, holding[:quantity]
    assert_in_delta 20.0, holding[:xirr_percent], 0.5
    assert_equal Money.new(10_000, "INR").format, holding[:invested]
    assert_equal Money.new(2_000, "INR").format, holding[:gain]
    assert_equal Money.new(10_000, "INR").format, result[:portfolio][:invested]
    assert_not_nil result[:portfolio][:xirr_percent]
  end

  test "an account without holdings has an empty list" do
    result = Assistant::Function::GetHoldings.new(@user).call

    assert_empty result[:accounts].find { |a| a[:name] == "Demat" }[:holdings]
    assert_nil result[:portfolio][:xirr_percent]
  end
end
