require "test_helper"

class PreciousMetalsControllerTest < ActionDispatch::IntegrationTest
  include AccountableResourceInterfaceTest

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:precious_metal)
  end

  test "creates gold with its value from price per gram x weight x purity" do
    assert_difference -> { Account.count } => 1, -> { PreciousMetal.count } => 1 do
      post precious_metals_path, params: {
        account: {
          name: "Gold coins",
          currency: "INR",
          subtype: "gold",
          accountable_type: "PreciousMetal",
          accountable_attributes: { weight_grams: 24, purity: "22k", form: "coins", price_per_gram: 7_200 }
        }
      }
    end

    created = Account.order(:created_at).last

    assert_equal 158_400, created.balance # 7,200 x 24 x 22/24
    assert_equal 158_400, created.opening_anchor_balance
    assert_equal 24, created.accountable.weight_grams
    assert_equal "22k", created.accountable.purity
  end

  test "entering a new price on edit records a valuation for today" do
    assert_difference -> { @account.entries.valuations.count } => 1 do
      patch precious_metal_path(@account), params: {
        account: {
          name: @account.name,
          accountable_type: "PreciousMetal",
          accountable_attributes: { id: @account.accountable_id, weight_grams: 10, purity: "24k", price_per_gram: 8_000 }
        }
      }
    end

    assert_redirected_to account_path(@account)
    assert_equal 80_000, @account.reload.balance
    assert_equal 80_000, @account.entries.valuations.order(:created_at).last.amount
  end

  test "editing details without a price leaves the value alone" do
    assert_no_difference -> { @account.entries.valuations.count } do
      patch precious_metal_path(@account), params: {
        account: {
          name: "Renamed",
          accountable_type: "PreciousMetal",
          accountable_attributes: { id: @account.accountable_id, form: "bars" }
        }
      }
    end

    assert_equal 300_000, @account.reload.balance
    assert_equal "bars", @account.accountable.form
  end

  test "shows the account page with its overview tab" do
    get account_path(@account, tab: "overview")

    assert_response :success
    assert_select "h4", text: "Purity"
  end
end
