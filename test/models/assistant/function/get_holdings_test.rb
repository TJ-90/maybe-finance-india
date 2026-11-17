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

  test "includes absolute return, 1-day change, CAGR and trailing returns" do
    fund = Security.create!(ticker: "900555", name: "Orchid Fund", exchange_operating_mic: Security::AMFI_MIC, kind: "mutual_fund")
    create_folio_trade @account, fund, qty: 100, price: 100, date: 2.years.ago.to_date
    set_price fund, 100, date: 2.years.ago.to_date
    set_price fund, 119, date: 1.day.ago.to_date
    set_price fund, 121, date: Date.current
    @account.holdings.create!(security: fund, date: Date.current, qty: 100, price: 121, amount: 12_100, currency: "INR")

    result = Assistant::Function::GetHoldings.new(@user).call
    holding = result[:accounts].find { |a| a[:name] == "Demat" }[:holdings].first

    assert_in_delta 21.0, holding[:absolute_return_percent], 0.1
    assert_in_delta 10.0, holding[:cagr_since_first_purchase_percent], 0.2
    assert_in_delta 1.7, holding[:one_day_change_percent], 0.1
    assert_not_nil holding[:one_day_change]
    assert_equal %w[1y 3y 5y], holding[:trailing_cagr_percent].keys
    assert_nil holding[:trailing_cagr_percent]["5y"]
    assert_match(/\APrices as of .* IST\z/, result[:portfolio][:prices_as_of])
  end

  test "an account without holdings has an empty list" do
    result = Assistant::Function::GetHoldings.new(@user).call

    assert_empty result[:accounts].find { |a| a[:name] == "Demat" }[:holdings]
    assert_nil result[:portfolio][:xirr_percent]
  end
end
