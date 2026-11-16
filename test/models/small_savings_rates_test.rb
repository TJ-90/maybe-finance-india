require "test_helper"

class SmallSavingsRatesTest < ActiveSupport::TestCase
  test "returns the rate in force on a date" do
    assert_equal BigDecimal("7.1"), SmallSavingsRates.rate_on(:ppf, Date.new(2025, 6, 1))
    assert_equal BigDecimal("8.15"), SmallSavingsRates.rate_on(:epf, Date.new(2023, 3, 31))
    assert_equal BigDecimal("8.25"), SmallSavingsRates.rate_on(:epf, Date.new(2023, 4, 1))
  end

  test "is nil before the first entry or for an unknown scheme" do
    assert_nil SmallSavingsRates.rate_on(:ppf, Date.new(2000, 1, 1))
    assert_nil SmallSavingsRates.rate_on(:unknown, Date.new(2025, 1, 1))
  end

  test "covers every scheme the app offers" do
    assert_equal %w[epf kvp nsc pomis ppf scss ssy], SmallSavingsRates.schemes.sort
  end
end
