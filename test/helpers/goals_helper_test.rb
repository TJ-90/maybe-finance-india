require "test_helper"

class GoalsHelperTest < ActionView::TestCase
  Snap = Struct.new(:date, :progress_pct)

  def snaps(*values)
    values.each_with_index.map { |value, index| Snap.new(Date.new(2026, 1, 1) + index, value) }
  end

  test "range follows the data with padding" do
    low, high = progress_chart_range(snaps(6, 7))

    assert_operator low, :<, 6
    assert_operator high, :>, 7
    assert_operator high - low, :<, 20
  end

  test "equal values and a single point get a band instead of an empty range" do
    [ snaps(40, 40, 40), snaps(40) ].each do |series|
      low, high = progress_chart_range(series)
      assert_operator high - low, :>=, 2
      assert_operator low, :<=, 40
      assert_operator high, :>=, 40
    end
  end

  test "range stays within 0 to 100" do
    low, high = progress_chart_range(snaps(0, 0))
    assert_equal 0, low
    assert_operator high, :>, 0

    low, high = progress_chart_range(snaps(100, 100))
    assert_equal 100, high
    assert_operator low, :<, 100
  end

  test "a small move fills the chart height" do
    ys = progress_polyline_points(snaps(6, 7)).split.map { |pair| pair.split(",").last.to_f }

    assert_operator (ys.first - ys.last).abs, :>, 20
  end

  test "a single point is drawn in the middle and equal values are a flat line inside the chart" do
    assert_match(/\A150\.0,/, progress_polyline_points(snaps(40)))

    ys = progress_polyline_points(snaps(40, 40)).split.map { |pair| pair.split(",").last.to_f }
    assert_equal ys.first, ys.last
    assert ys.all? { |y| y.between?(0, 80) }
  end
end
