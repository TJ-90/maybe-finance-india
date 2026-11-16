require "test_helper"

class Holding::TaxLotsTest < ActiveSupport::TestCase
  include TaxTestHelper

  setup do
    @family = inr_family
    @account = create_investment_account(@family)
    @fund = create_tax_security("FUNDA")
    @other = create_tax_security("FUNDB")
  end

  test "open lots keep buy date, units and cost per unit" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2023, 1, 10)
    create_folio_trade @account, @fund, qty: 5, price: 120, date: Date.new(2023, 6, 10)

    lots = Holding::TaxLots.new([ @account ], currency: "INR")

    assert_equal [ 10, 5 ], lots.open_lots.map(&:qty)
    assert_equal [ 100, 120 ], lots.open_lots.map(&:cost_per_unit)
    assert_equal Date.new(2023, 1, 10), lots.open_lots.first.buy_date
    assert_empty lots.realized_lots
  end

  test "a partial sell spans lots first in first out" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2022, 1, 10)
    create_folio_trade @account, @fund, qty: 10, price: 150, date: Date.new(2022, 6, 10)
    create_folio_trade @account, @fund, qty: -15, price: 200, date: Date.new(2023, 8, 1)

    lots = Holding::TaxLots.new([ @account ], currency: "INR")

    assert_equal 2, lots.realized_lots.size
    first, second = lots.realized_lots
    assert_equal [ Date.new(2022, 1, 10), 10 ], [ first.buy_date, first.qty ]
    assert_equal [ 1000, 2000, 1000 ], [ first.cost, first.proceeds, first.gain ]
    assert_equal [ Date.new(2022, 6, 10), 5 ], [ second.buy_date, second.qty ]
    assert_equal [ 750, 1000, 250 ], [ second.cost, second.proceeds, second.gain ]
    assert_equal 568, first.holding_days

    assert_equal 1, lots.open_lots.size
    assert_equal 5, lots.open_lots.first.qty
    assert_equal 150, lots.open_lots.first.cost_per_unit
    assert_equal Date.new(2022, 6, 10), lots.open_lots.first.buy_date
  end

  test "one row per redemption nets all consumed lots" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2022, 1, 10)
    create_folio_trade @account, @fund, qty: 10, price: 150, date: Date.new(2022, 6, 10)
    create_folio_trade @account, @fund, qty: -15, price: 200, date: Date.new(2023, 8, 1)
    create_folio_trade @account, @fund, qty: -5, price: 90, date: Date.new(2023, 9, 1)

    redemptions = Holding::TaxLots.new([ @account ], currency: "INR").redemptions

    assert_equal 2, redemptions.size
    assert_equal [ 15, 3000, 1750, 1250 ], [ redemptions[0].qty, redemptions[0].proceeds, redemptions[0].cost, redemptions[0].gain ]
    assert_equal [ 5, 450, 750, -300 ], [ redemptions[1].qty, redemptions[1].proceeds, redemptions[1].cost, redemptions[1].gain ]
  end

  test "folios of the same scheme are separate FIFO queues" do
    create_folio_trade @account, @fund, qty: 10, price: 100, date: Date.new(2022, 1, 10), folio: "1111"
    create_folio_trade @account, @fund, qty: 10, price: 200, date: Date.new(2022, 2, 10), folio: "2222"
    create_folio_trade @account, @fund, qty: -5, price: 300, date: Date.new(2023, 8, 1), folio: "2222"

    lots = Holding::TaxLots.new([ @account ], currency: "INR")

    assert_equal 1, lots.realized_lots.size
    assert_equal "2222", lots.realized_lots.first.folio
    assert_equal 1000, lots.realized_lots.first.cost # 5 units from the 2222 lot at 200, not from folio 1111

    by_folio = lots.open_lots.index_by(&:folio)
    assert_equal 10, by_folio["1111"].qty
    assert_equal 5, by_folio["2222"].qty
  end

  test "a switch-out is a redemption and the switch-in is a new lot" do
    create_folio_trade @account, @fund, qty: 100, price: 10, date: Date.new(2022, 1, 10), folio: "1111"
    create_folio_trade @account, @fund, qty: -100, price: 15, date: Date.new(2023, 5, 1), folio: "1111" # switch out
    create_folio_trade @account, @other, qty: 75, price: 20, date: Date.new(2023, 5, 1), folio: "1111" # switch in

    lots = Holding::TaxLots.new([ @account ], currency: "INR")

    assert_equal 1, lots.redemptions.size
    assert_equal 500, lots.redemptions.first.gain
    assert_equal [ @other ], lots.open_lots.map(&:security)
    assert_equal 20, lots.open_lots.first.cost_per_unit
  end

  test "sells with no matching lots are reported and ignored" do
    create_folio_trade @account, @fund, qty: 5, price: 100, date: Date.new(2023, 1, 10)
    create_folio_trade @account, @fund, qty: -8, price: 120, date: Date.new(2023, 6, 10)

    lots = Holding::TaxLots.new([ @account ], currency: "INR")

    assert_equal 5, lots.realized_lots.sum(&:qty)
    assert_equal 3, lots.unmatched_sales.first[:qty]
    assert_empty lots.open_lots
  end

  test "same day buy is matched before a same day sell" do
    create_folio_trade @account, @fund, qty: -5, price: 110, date: Date.new(2023, 6, 10)
    create_folio_trade @account, @fund, qty: 5, price: 100, date: Date.new(2023, 6, 10)

    lots = Holding::TaxLots.new([ @account ], currency: "INR")

    assert_equal 1, lots.realized_lots.size
    assert_empty lots.unmatched_sales
  end

  test "fractional units" do
    create_folio_trade @account, @fund, qty: BigDecimal("10.5"), price: 100, date: Date.new(2023, 1, 10)
    create_folio_trade @account, @fund, qty: BigDecimal("-0.25"), price: 100, date: Date.new(2023, 2, 10)

    assert_equal BigDecimal("10.25"), Holding::TaxLots.new([ @account ], currency: "INR").open_lots.first.qty
  end
end
