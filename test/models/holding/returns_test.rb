require "test_helper"

class Holding::ReturnsTest < ActiveSupport::TestCase
  include TaxTestHelper

  setup do
    travel_to Date.new(2026, 11, 16)
    @family = inr_family
    @account = create_investment_account(@family)
    @fund = create_tax_security("RETFUND")
  end

  def holding_for(security, qty:, price:)
    @account.holdings.create!(security: security, date: Date.current, qty: qty, price: price, amount: qty * price, currency: "INR")
  end

  test "invested is the FIFO cost of the units still held" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2025, 1, 1)
    create_folio_trade @account, @fund, qty: 10, price: 200, date: Date.new(2025, 6, 1)
    create_folio_trade @account, @fund, qty: -12, price: 250, date: Date.new(2025, 9, 1)
    holding = holding_for(@fund, qty: 8, price: 300)

    returns = holding.returns

    assert_equal Money.new(1600, "INR"), returns.invested # 8 units left of the 200 lot
    assert_equal Money.new(2400, "INR"), returns.current_value
    assert_equal Money.new(800, "INR"), returns.gain
    assert_in_delta 0.5, returns.absolute_return, 1e-9
  end

  test "absolute return is nil when nothing is invested" do
    holding = holding_for(@fund, qty: 5, price: 100)

    assert_nil holding.returns.absolute_return
  end

  test "one day change compares the latest price with the one before it" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2026, 10, 1)
    set_price @fund, 100, date: Date.new(2026, 11, 14)
    set_price @fund, 110, date: Date.new(2026, 11, 16)
    holding = holding_for(@fund, qty: 10, price: 110)

    returns = holding.returns

    assert_in_delta 0.10, returns.one_day_change_percent, 1e-9
    assert_in_delta 100, returns.one_day_change.amount, 1e-6 # 1100 now, 1000 before
  end

  test "one day change is nil with a single stored price" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2026, 10, 1)
    set_price @fund, 110, date: Date.new(2026, 11, 16)

    returns = holding_for(@fund, qty: 10, price: 110).returns

    assert_nil returns.one_day_change_percent
    assert_nil returns.one_day_change
  end

  test "CAGR since the first purchase uses stored prices" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2024, 11, 16)
    set_price @fund, 100, date: Date.new(2024, 11, 16)
    set_price @fund, 144, date: Date.new(2026, 11, 16)
    holding = holding_for(@fund, qty: 10, price: 144)

    assert_in_delta 0.2, holding.returns.cagr_since_first_purchase, 1e-3 # 1.44 over exactly two years
  end

  test "CAGR since the first purchase falls back to the price paid when no price is stored for that day" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2024, 11, 16)
    set_price @fund, 121, date: Date.new(2026, 11, 16)
    holding = holding_for(@fund, qty: 10, price: 121)

    assert_in_delta 0.1, holding.returns.cagr_since_first_purchase, 1e-3
  end

  test "CAGR is nil when the security has been held under a year" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2026, 3, 1)
    set_price @fund, 130, date: Date.new(2026, 11, 16)
    holding = holding_for(@fund, qty: 10, price: 130)

    assert_nil holding.returns.cagr_since_first_purchase
    assert_in_delta 0.7, holding.returns.years_held, 0.05
  end

  test "CAGR counts from the first purchase even after part of the units were sold" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2024, 11, 16)
    create_folio_trade @account, @fund, qty: -10, price: 120, date: Date.new(2025, 5, 1)
    create_folio_trade @account, @fund, qty: 5, price: 130, date: Date.new(2026, 5, 1)
    set_price @fund, 100, date: Date.new(2024, 11, 16)
    set_price @fund, 121, date: Date.new(2026, 11, 16)
    holding = holding_for(@fund, qty: 5, price: 121)

    assert_equal Date.new(2024, 11, 16), holding.returns.first_purchase_date
    assert_in_delta 0.1, holding.returns.cagr_since_first_purchase, 1e-3
  end

  test "holdings that share an account instance replay the trades once" do
    other = create_tax_security("OTHERFUND")
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2025, 1, 1)
    create_folio_trade @account, other, qty: 10, price: 100, date: Date.new(2025, 1, 1)
    holding_for(@fund, qty: 10, price: 110)
    holding_for(other, qty: 10, price: 120)

    lots = Holding::TaxLots.new([ @account ], currency: "INR")
    Holding::TaxLots.expects(:new).once.returns(lots)

    holdings = Account.find(@account.id).current_holdings_with_returns
    assert_equal [ 1200, 1100 ], holdings.map { |h| h.returns.current_value.amount.to_i }
    assert_equal [ 200, 100 ], holdings.map { |h| h.returns.gain.amount.to_i }
  end
end
