require "test_helper"

class Account::ReturnsTest < ActiveSupport::TestCase
  include TaxTestHelper

  setup do
    travel_to Date.new(2026, 1, 1)
    @family = inr_family
    @account = create_investment_account(@family)
    @fund = create_tax_security("XIRRFUND")
  end

  def add_holding(account, security, qty:, price:)
    account.holdings.create!(security: security, date: Date.current, qty: qty, price: price, amount: qty * price, currency: "INR")
  end

  test "trade cash flows are negative for buys and positive for sells" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2025, 1, 1)
    create_folio_trade @account, @fund, qty: -4, price: 150, date: Date.new(2025, 7, 1)

    assert_equal [ [ Date.new(2025, 1, 1), -1000 ], [ Date.new(2025, 7, 1), 600 ] ], @account.trade_cash_flows.sort
  end

  test "account xirr treats the current holdings value as a terminal inflow" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2025, 1, 1)
    add_holding @account, @fund, qty: 10, price: 110

    assert_in_delta 0.10, @account.xirr, 1e-4
  end

  test "account xirr includes money taken out by sells" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2025, 1, 1)
    create_folio_trade @account, @fund, qty: -10, price: 120, date: Date.new(2025, 7, 2)

    expected = Xirr.new([ [ Date.new(2025, 1, 1), -1000 ], [ Date.new(2025, 7, 2), 1200 ] ]).rate

    assert_in_delta expected, @account.xirr, 1e-9
  end

  test "account xirr is nil without trades or without a current value or exit" do
    assert_nil @account.xirr

    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2025, 1, 1)
    assert_nil @account.xirr # buy only, nothing held and nothing sold
  end

  test "holding xirr only looks at its own security" do
    other = create_tax_security("OTHERFUND")
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2025, 1, 1)
    create_folio_trade @account, other, qty: 10, price: 100, date: Date.new(2025, 1, 1)
    holding = add_holding(@account, @fund, qty: 10, price: 120)
    add_holding @account, other, qty: 10, price: 50

    assert_in_delta 0.20, holding.xirr, 1e-4
  end

  test "portfolio xirr combines accounts" do
    second = create_investment_account(@family, name: "Second")
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2025, 1, 1)
    create_folio_trade second, @fund, qty: 10, price: 100, date: Date.new(2025, 1, 1)
    add_holding @account, @fund, qty: 10, price: 120
    add_holding second, @fund, qty: 10, price: 100

    # 2000 in, 2200 out after one year
    assert_in_delta 0.10, @family.portfolio_xirr(accounts: [ @account, second ]), 1e-4
    assert_nil @family.portfolio_xirr(accounts: [])
  end

  test "investment summary reports invested, current value, gain and xirr" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2025, 1, 1)
    add_holding @account, @fund, qty: 10, price: 110

    summary = @family.investment_summary(accounts: [ @account ])

    assert summary.any?
    assert_equal 1000, summary.invested.amount
    assert_equal 1100, summary.current_value.amount
    assert_equal 100, summary.gain.amount
    assert_in_delta 0.10, summary.gain_percent, 1e-9
    assert_in_delta 0.10, summary.xirr, 1e-4
  end
end
