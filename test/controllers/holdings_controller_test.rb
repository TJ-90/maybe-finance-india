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
    assert_select "p", text: "XIRR / 1D / CAGR"
    assert_select "p", text: /\A\d+\.\d%\z/
  end

  test "holdings table shows 1-day change, CAGR since first purchase and when prices were refreshed" do
    family = inr_family
    account = create_investment_account(family)
    fund = create_tax_security("CAGRCOL")
    create_folio_trade account, fund, qty: 10, price: 100, date: 2.years.ago.to_date
    set_price fund, 100, date: 2.years.ago.to_date
    set_price fund, 110, date: 1.day.ago.to_date
    set_price fund, 121, date: Date.current
    account.holdings.create!(security: fund, date: Date.current, qty: 10, price: 121, amount: 1210, currency: "INR")

    get holdings_url(account_id: account.id)

    assert_response :success
    assert_select "p", text: "1D 10.0%"
    assert_select "p", text: "CAGR 10.0%"
    assert_select "[data-testid=holdings-prices-as-of]", text: /Prices as of .* IST/
  end

  test "CAGR shows a dash for a holding under a year old" do
    family = inr_family
    account = create_investment_account(family)
    fund = create_tax_security("YOUNGFUND")
    create_folio_trade account, fund, qty: 10, price: 100, date: 3.months.ago.to_date
    account.holdings.create!(security: fund, date: Date.current, qty: 10, price: 121, amount: 1210, currency: "INR")

    get holdings_url(account_id: account.id)

    assert_select "p", text: "CAGR --"
  end

  test "mutual fund holdings show trailing CAGR" do
    family = inr_family
    account = create_investment_account(family)
    fund = Security.create!(ticker: "900777", name: "Trail Fund", exchange_operating_mic: Security::AMFI_MIC, kind: "mutual_fund")
    create_folio_trade account, fund, qty: 10, price: 100, date: 2.years.ago.to_date
    set_price fund, 100, date: 1.year.ago.to_date
    set_price fund, 120, date: Date.current
    account.holdings.create!(security: fund, date: Date.current, qty: 10, price: 120, amount: 1200, currency: "INR")

    get holdings_url(account_id: account.id)

    assert_select "p", text: "1Y 20.0% · 3Y -- · 5Y --"
  end
end
