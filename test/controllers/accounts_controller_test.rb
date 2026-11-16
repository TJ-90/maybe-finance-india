require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  include TaxTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:depository)
  end

  test "should get index" do
    get accounts_url
    assert_response :success
  end

  test "should get show" do
    get account_url(@account)
    assert_response :success
  end

  test "investment account overview shows invested, value, gain and XIRR" do
    family = inr_family
    account = create_investment_account(family)
    fund = create_tax_security("OVERVIEW")
    create_folio_trade account, fund, qty: 10, price: 100, date: 1.year.ago.to_date
    account.holdings.create!(security: fund, date: Date.current, qty: 10, price: 120, amount: 1200, currency: "INR")

    get account_url(account)

    assert_response :success
    assert_select "#account-investment-summary", text: /Invested/
    assert_select "#account-investment-summary", text: /XIRR/
    assert_select "#account-investment-summary", text: /20\.\d%/
  end

  test "new account picker offers the Indian instrument types" do
    get new_account_url

    assert_response :success
    assert_select "a[href*='fixed_deposits/new']"
    assert_select "a[href*='provident_funds/new']"
    assert_select "a[href*='precious_metals/new']"
  end

  test "should sync account" do
    post sync_account_url(@account)
    assert_redirected_to account_url(@account)
  end

  test "should get sparkline" do
    get sparkline_account_url(@account)
    assert_response :success
  end

  test "destroys account" do
    delete account_url(@account)
    assert_redirected_to accounts_path
    assert_enqueued_with job: DestroyJob
    assert_equal "Account scheduled for deletion", flash[:notice]
  end
end
