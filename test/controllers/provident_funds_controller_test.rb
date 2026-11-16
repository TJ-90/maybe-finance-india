require "test_helper"

class ProvidentFundsControllerTest < ActionDispatch::IntegrationTest
  include AccountableResourceInterfaceTest

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:provident_fund)
  end

  test "creates a provident fund dated on its opening date" do
    assert_difference -> { Account.count } => 1, -> { ProvidentFund.count } => 1 do
      post provident_funds_path, params: {
        account: {
          name: "My EPF",
          balance: 450_000,
          currency: "INR",
          subtype: "epf",
          accountable_type: "ProvidentFund",
          accountable_attributes: {
            opened_on: "2025-04-01",
            monthly_contribution: 6_000,
            employer_contribution: 6_000,
            account_number_last4: "4321"
          }
        }
      }
    end

    created = Account.order(:created_at).last

    assert_equal 450_000, created.opening_anchor_balance
    assert_equal Date.new(2025, 4, 1), created.opening_anchor_date
    assert_equal "4321", created.accountable.account_number_last4
    assert_nil created.accountable.interest_rate
    assert_equal 8.25, created.accountable.rate_on(Date.new(2025, 6, 1))
  end

  test "updates the interest rate override" do
    patch provident_fund_path(@account), params: {
      account: {
        name: @account.name,
        accountable_type: "ProvidentFund",
        accountable_attributes: { id: @account.accountable_id, interest_rate: 7.5 }
      }
    }

    assert_redirected_to account_path(@account)
    assert_equal 7.5, @account.reload.accountable.rate_on(Date.current)
  end

  test "shows the account page with its overview tab" do
    get account_path(@account, tab: "overview")

    assert_response :success
    assert_select "h4", text: "Interest method"
  end
end
