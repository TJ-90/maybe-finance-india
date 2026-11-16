require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include TaxTestHelper

  setup do
    sign_in @user = users(:family_admin)
  end

  test "dashboard" do
    get root_path
    assert_response :ok
  end

  test "dashboard shows the net worth breakdown and upcoming premiums" do
    get root_path

    assert_response :ok
    assert_select "#net-worth-breakdown", text: /Market assets/
    assert_select "#net-worth-breakdown", text: /Retirement funds/
    assert_select "#upcoming-premiums", text: /Example Life Insurance/
    assert_select "#upcoming-premiums", text: /Example Health Insurance/, count: 0 # due in 200 days
  end

  test "dashboard hides the upcoming premiums card when none are due" do
    insurance_policies(:term).update!(next_premium_due_on: 90.days.from_now.to_date)

    get root_path

    assert_response :ok
    assert_select "#upcoming-premiums", count: 0
  end

  test "dashboard shows the Investments card with XIRR when there are trades" do
    family = inr_family
    account = create_investment_account(family)
    fund = create_tax_security("DASHFUND")
    create_folio_trade account, fund, qty: 10, price: 100, date: 1.year.ago.to_date
    account.holdings.create!(security: fund, date: Date.current, qty: 10, price: 110, amount: 1100, currency: "INR")

    get root_path

    assert_response :ok
    assert_select "#dashboard-investments", text: /Invested/
    assert_select "#dashboard-investments", text: /Current value/
    assert_select "#dashboard-investments", text: /Gain/
    assert_select "#dashboard-investments", text: /XIRR/
  end

  test "dashboard hides the Investments card without holdings" do
    Holding.destroy_all
    Entry.where(entryable_type: "Trade").destroy_all

    get root_path

    assert_response :ok
    assert_select "#dashboard-investments", count: 0
  end

  test "changelog" do
    VCR.use_cassette("git_repository_provider/fetch_latest_release_notes") do
      get changelog_path
      assert_response :ok
    end
  end

  test "changelog with nil release notes" do
    # Mock the GitHub provider to return nil (simulating API failure or no releases)
    github_provider = mock
    github_provider.expects(:fetch_latest_release_notes).returns(nil)
    Provider::Registry.stubs(:get_provider).with(:github).returns(github_provider)

    get changelog_path
    assert_response :ok
    assert_select "h2", text: "Release notes unavailable"
    assert_select "a[href='https://github.com/maybe-finance/maybe/releases']"
  end

  test "changelog with incomplete release notes" do
    # Mock the GitHub provider to return incomplete data (missing some fields)
    github_provider = mock
    incomplete_data = {
      avatar: nil,
      username: "maybe-finance",
      name: "Test Release",
      published_at: nil,
      body: nil
    }
    github_provider.expects(:fetch_latest_release_notes).returns(incomplete_data)
    Provider::Registry.stubs(:get_provider).with(:github).returns(github_provider)

    get changelog_path
    assert_response :ok
    assert_select "h2", text: "Test Release"
    # Should not crash even with nil values
  end
end
