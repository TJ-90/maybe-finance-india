require "test_helper"

class HoldingsControllerTest < ActionDispatch::IntegrationTest
  include TaxTestHelper

  setup do
    sign_in users(:family_admin)
    @account = accounts(:investment)
    @holding = @account.holdings.first
  end

  test "gets holdings" do
    get holdings_url(account_id: @account.id)
    assert_response :success
  end

  test "gets holding" do
    get holding_path(@holding)

    assert_response :success
  end

  test "destroys holding and associated entries" do
    assert_difference -> { Holding.count } => -1,
                      -> { Entry.count } => -1 do
      delete holding_path(@holding)
    end

    assert_redirected_to account_path(@holding.account)
    assert_empty @holding.account.entries.where(entryable: @holding.account.trades.where(security: @holding.security))
  end

  test "holdings table shows an XIRR column" do
    family = inr_family
    account = create_investment_account(family)
    fund = create_tax_security("XIRRCOL")
    create_folio_trade account, fund, qty: 10, price: 100, date: 1.year.ago.to_date
    account.holdings.create!(security: fund, date: Date.current, qty: 10, price: 120, amount: 1200, currency: "INR")

    get holdings_url(account_id: account.id)

    assert_response :success
    assert_select "p", text: "XIRR"
    assert_select "p", text: /\A\d+\.\d%\z/
  end
end
