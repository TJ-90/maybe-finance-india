require "test_helper"

class Security::TrailingReturnsTest < ActiveSupport::TestCase
  setup do
    @latest = Date.new(2026, 11, 13) # a Friday
  end

  def history(prices)
    prices.map { |date, price| [ date, price ] }
  end

  test "CAGR over 1, 3 and 5 years from a NAV history" do
    returns = Security::TrailingReturns.from_history(history(
      Date.new(2021, 11, 13) => 100,
      Date.new(2023, 11, 13) => 150,
      Date.new(2025, 11, 13) => 200,
      @latest => 220
    ))

    assert_in_delta 0.10, returns.cagr(1), 1e-9
    assert_in_delta((220.0 / 150)**(1.0 / 3) - 1, returns.cagr(3), 1e-9)
    assert_in_delta((220.0 / 100)**(1.0 / 5) - 1, returns.cagr(5), 1e-9)
    assert_equal [ 1, 3, 5 ], returns.to_h.keys
    assert_equal @latest, returns.as_of
  end

  test "uses the last price on or before the start date, within a weekend or holiday gap" do
    # 2025-11-13 is a Thursday with no price; Wednesday's is used
    returns = Security::TrailingReturns.from_history(history(Date.new(2025, 11, 12) => 200, @latest => 220))

    assert_in_delta 0.10, returns.cagr(1), 1e-9
  end

  test "is nil when the history does not reach back far enough" do
    returns = Security::TrailingReturns.from_history(history(Date.new(2025, 11, 1) => 200, @latest => 220))
    assert_nil returns.cagr(1) # the start price is 12 days before the target

    returns = Security::TrailingReturns.from_history(history(Date.new(2026, 1, 5) => 200, @latest => 220))
    assert_nil returns.cagr(1)
    assert_nil returns.cagr(5)
  end

  test "is nil without any price" do
    assert_nil Security::TrailingReturns.from_history([]).cagr(1)
    assert_equal({ 1 => nil, 3 => nil, 5 => nil }, Security::TrailingReturns.from_history([]).to_h)
  end

  test "reads stored security prices" do
    security = Security.create!(ticker: "TRAIL1", exchange_operating_mic: "AMFI", kind: "mutual_fund")
    Security::Price.create!(security: security, date: Date.new(2023, 11, 13), price: 100, currency: "INR")
    Security::Price.create!(security: security, date: Date.new(2025, 11, 13), price: 120, currency: "INR")
    Security::Price.create!(security: security, date: @latest, price: 144, currency: "INR")

    returns = security.trailing_returns

    assert_in_delta 0.2, returns.cagr(1), 1e-9
    assert_in_delta 1.44**(1.0 / 3) - 1, returns.cagr(3), 1e-9
    assert_nil returns.cagr(5)
  end

  test "a security without prices has no trailing returns" do
    security = Security.create!(ticker: "TRAIL2", exchange_operating_mic: "AMFI", kind: "mutual_fund")

    assert_equal({ 1 => nil, 3 => nil, 5 => nil }, security.trailing_returns.to_h)
  end
end
