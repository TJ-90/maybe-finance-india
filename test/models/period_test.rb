require "test_helper"

class PeriodTest < ActiveSupport::TestCase
  test "raises validation error when start_date or end_date is missing" do
    error = assert_raises(ActiveModel::ValidationError) do
      Period.new(start_date: nil, end_date: nil)
    end

    assert_includes error.message, "Start date can't be blank"
    assert_includes error.message, "End date can't be blank"
  end

  test "raises validation error when start_date is not before end_date" do
    error = assert_raises(ActiveModel::ValidationError) do
      Period.new(start_date: Date.current, end_date: Date.current - 1.day)
    end

    assert_includes error.message, "Start date must be before end date"
  end

  test "can create custom period" do
    period = Period.new(start_date: Date.current - 15.days, end_date: Date.current)
    assert_equal "Custom Period", period.label
  end

  test "from_key returns period for valid key" do
    period = Period.from_key("last_30_days")
    assert_equal 30.days.ago.to_date, period.start_date
    assert_equal Date.current, period.end_date
  end

  test "from_key with invalid key and no fallback raises error" do
    error = assert_raises(Period::InvalidKeyError) do
      Period.from_key("invalid_key")
    end
  end

  test "label returns correct label for known period" do
    period = Period.from_key("last_30_days")
    assert_equal "Last 30 Days", period.label
  end

  test "label returns Custom Period for unknown period" do
    period = Period.new(start_date: Date.current - 15.days, end_date: Date.current)
    assert_equal "Custom Period", period.label
  end

  test "comparison_label returns correct label for known period" do
    period = Period.from_key("last_30_days")
    assert_equal "vs. last month", period.comparison_label
  end

  test "comparison_label returns date range for unknown period" do
    start_date = Date.current - 15.days
    end_date = Date.current
    period = Period.new(start_date: start_date, end_date: end_date)
    expected = "#{start_date.strftime("%b %d, %Y")} to #{end_date.strftime("%b %d, %Y")}"
    assert_equal expected, period.comparison_label
  end

  test "current financial year runs from April 1 to today" do
    travel_to Date.new(2026, 11, 16) do
      period = Period.current_financial_year
      assert_equal Date.new(2026, 4, 1), period.start_date
      assert_equal Date.new(2026, 11, 16), period.end_date
      assert_equal "FYTD", period.label_short
      assert_equal "Current FY (2026-27)", period.label
    end

    travel_to Date.new(2027, 2, 10) do
      period = Period.current_financial_year
      assert_equal Date.new(2026, 4, 1), period.start_date
      assert_equal Date.new(2027, 2, 10), period.end_date
      assert_equal "Current FY (2026-27)", period.label
    end
  end

  test "financial year boundary on April 1 and March 31" do
    travel_to Date.new(2026, 4, 1) do
      assert_equal Date.new(2026, 4, 1), Period.current_financial_year.start_date
    end

    travel_to Date.new(2026, 3, 31) do
      assert_equal Date.new(2025, 4, 1), Period.current_financial_year.start_date
      assert_equal "Current FY (2025-26)", Period.current_financial_year.label
    end
  end

  test "last financial year covers the whole previous April to March" do
    travel_to Date.new(2026, 11, 16) do
      period = Period.last_financial_year
      assert_equal Date.new(2025, 4, 1), period.start_date
      assert_equal Date.new(2026, 3, 31), period.end_date
      assert_equal "Last FY", period.label_short
    end

    travel_to Date.new(2027, 2, 10) do
      assert_equal Date.new(2025, 4, 1), Period.last_financial_year.start_date
      assert_equal Date.new(2026, 3, 31), Period.last_financial_year.end_date
    end
  end

  test "financial_year_for returns the full financial year containing a date" do
    period = Period.financial_year_for(Date.new(2027, 3, 31))
    assert_equal Date.new(2026, 4, 1), period.start_date
    assert_equal Date.new(2027, 3, 31), period.end_date

    period = Period.financial_year_for(Date.new(2027, 4, 1))
    assert_equal Date.new(2027, 4, 1), period.start_date
    assert_equal Date.new(2028, 3, 31), period.end_date

    assert_equal "2026-27", Period.financial_year_label(Date.new(2027, 3, 31))
    assert_equal "2099-00", Period.financial_year_label(Date.new(2099, 6, 1))
  end

  test "financial year periods appear in selector options" do
    keys = Period.as_options.map(&:last)
    assert_includes keys, "current_financial_year"
    assert_includes keys, "last_financial_year"
  end
end
