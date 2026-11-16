require "test_helper"

class FixedDepositsControllerTest < ActionDispatch::IntegrationTest
  include AccountableResourceInterfaceTest

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:fixed_deposit)
  end

  def deposit_params(overrides = {})
    {
      account: {
        name: "SBI FD",
        currency: "INR",
        subtype: "fd",
        accountable_type: "FixedDeposit",
        accountable_attributes: {
          institution_name: "SBI",
          principal: 100_000,
          interest_rate: 7,
          compounding: "quarterly",
          payout: "cumulative",
          start_date: 1.month.ago.to_date,
          maturity_date: 11.months.from_now.to_date,
          auto_renew: "0"
        }
      }.deep_merge(overrides)
    }
  end

  test "creates a fixed deposit with its principal as the opening balance" do
    assert_difference -> { Account.count } => 1, -> { FixedDeposit.count } => 1 do
      post fixed_deposits_path, params: deposit_params
    end

    created = Account.order(:created_at).last

    assert_equal 100_000, created.balance
    assert_equal 100_000, created.opening_anchor_balance
    assert_equal 1.month.ago.to_date, created.opening_anchor_date
    assert_equal "SBI", created.accountable.institution_name
    assert_equal 7, created.accountable.interest_rate
    assert_redirected_to created
    assert_enqueued_with(job: SyncJob)
  end

  test "creates a recurring deposit from the monthly installment" do
    post fixed_deposits_path, params: deposit_params(
      subtype: "rd", accountable_attributes: { principal: "", monthly_installment: 5_000 }
    )

    created = Account.order(:created_at).last

    assert_equal "rd", created.subtype
    assert_equal 5_000, created.opening_anchor_balance
  end

  test "updates deposit terms" do
    patch fixed_deposit_path(@account), params: {
      account: {
        name: "Renamed FD",
        accountable_type: "FixedDeposit",
        accountable_attributes: { id: @account.accountable_id, interest_rate: 7.5, institution_name: "ICICI" }
      }
    }

    assert_redirected_to account_path(@account)
    assert_equal "Renamed FD", @account.reload.name
    assert_equal 7.5, @account.accountable.interest_rate
    assert_equal "ICICI", @account.accountable.institution_name
  end

  test "shows the deposit page with its overview tab" do
    get account_path(@account, tab: "overview")

    assert_response :success
    assert_select "h4", text: "Interest rate"
  end
end
