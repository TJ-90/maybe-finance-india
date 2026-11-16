require "test_helper"

class Goal::GlidePathTest < ActiveSupport::TestCase
  setup do
    @target = Date.new(2036, 6, 30)
    @glide_path = Goal::GlidePath.new(
      initial_equity_pct: 70, final_equity_pct: 30, glide_path_years: 5, target_date: @target
    )
  end

  test "holds the initial equity share until the glide path starts" do
    assert_equal 70, @glide_path.equity_pct_for(Date.new(2026, 1, 1))
    assert_equal 70, @glide_path.equity_pct_for(@target - 5.years)
  end

  test "de-risks linearly between the start and the target date" do
    start = @target - 5.years
    days = (@target - start).to_i

    assert_in_delta 50.0, @glide_path.equity_pct_for(start + (days / 2.0).round.days), 0.05
    assert_in_delta 60.0, @glide_path.equity_pct_for(start + (days / 4.0).round.days), 0.05
    assert_in_delta 30.0, @glide_path.equity_pct_for(@target - 1.day), 0.05
  end

  test "uses the final equity share on and after the target date" do
    assert_equal 30, @glide_path.equity_pct_for(@target)
    assert_equal 30, @glide_path.equity_pct_for(@target + 2.years)
  end

  test "a zero-year glide path switches on the target date" do
    flat = Goal::GlidePath.new(initial_equity_pct: 80, final_equity_pct: 20, glide_path_years: 0, target_date: @target)

    assert_equal 80, flat.equity_pct_for(@target - 1.day)
    assert_equal 20, flat.equity_pct_for(@target)
  end

  test "debt share is the complement of equity" do
    assert_equal 30, @glide_path.debt_pct_for(Date.new(2026, 1, 1))
  end

  test "table has a row per year ending on the target date" do
    rows = @glide_path.table(from: Date.new(2031, 6, 30))

    assert_equal [ Date.new(2031, 6, 30), Date.new(2032, 6, 30), Date.new(2033, 6, 30), Date.new(2034, 6, 30), Date.new(2035, 6, 30), @target ], rows.map(&:date)
    assert_equal 70, rows.first.equity_pct
    assert_equal 30, rows.last.equity_pct
  end
end
