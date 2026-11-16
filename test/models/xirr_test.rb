require "test_helper"

class XirrTest < ActiveSupport::TestCase
  test "matches the Excel documentation example" do
    flows = [
      [ Date.new(2008, 1, 1), -10_000 ],
      [ Date.new(2008, 3, 1), 2_750 ],
      [ Date.new(2008, 10, 30), 4_250 ],
      [ Date.new(2009, 2, 15), 3_250 ],
      [ Date.new(2009, 4, 1), 2_750 ]
    ]

    assert_in_delta 0.373362535, Xirr.new(flows).rate, 1e-6
  end

  test "one year, ten percent" do
    rate = Xirr.new([ [ Date.new(2023, 1, 1), -1000 ], [ Date.new(2024, 1, 1), 1100 ] ]).rate

    assert_in_delta 0.10, rate, 1e-6
  end

  test "negative returns" do
    rate = Xirr.new([ [ Date.new(2023, 1, 1), -1000 ], [ Date.new(2024, 1, 1), 800 ] ]).rate

    assert_in_delta(-0.20, rate, 1e-6)
  end

  test "flow order does not matter" do
    flows = [ [ Date.new(2024, 1, 1), 1100 ], [ Date.new(2023, 1, 1), -1000 ] ]

    assert_in_delta 0.10, Xirr.new(flows).rate, 1e-6
  end

  test "very high returns still converge" do
    rate = Xirr.new([ [ Date.new(2024, 1, 1), -1000 ], [ Date.new(2024, 3, 1), 1500 ] ]).rate

    assert_in_delta((1.5**(365.0 / 60)) - 1, rate, 1e-4)
  end

  test "nil when all flows share a sign" do
    assert_nil Xirr.new([ [ Date.new(2023, 1, 1), -1000 ], [ Date.new(2024, 1, 1), -10 ] ]).rate
    assert_nil Xirr.new([ [ Date.new(2023, 1, 1), 1000 ], [ Date.new(2024, 1, 1), 10 ] ]).rate
  end

  test "nil with fewer than two non-zero flows" do
    assert_nil Xirr.new([]).rate
    assert_nil Xirr.new([ [ Date.new(2023, 1, 1), -1000 ] ]).rate
    assert_nil Xirr.new([ [ Date.new(2023, 1, 1), -1000 ], [ Date.new(2024, 1, 1), 0 ] ]).rate
  end

  test "near total loss never raises" do
    rate = Xirr.new([ [ Date.new(2023, 1, 1), -1000 ], [ Date.new(2024, 1, 1), 0.01 ] ]).rate

    assert rate.nil? || rate < -0.99
  end
end
