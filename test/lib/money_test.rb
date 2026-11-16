require "test_helper"
require "ostruct"

class MoneyTest < ActiveSupport::TestCase
  test "can create with default currency" do
    value = Money.new(1000)
    assert_equal 1000, value.amount
  end

  test "can create with custom currency" do
    value1 = Money.new(1000, :EUR)
    value2 = Money.new(1000, :eur)
    value3 = Money.new(1000, "eur")
    value4 = Money.new(1000, "EUR")

    assert_equal value1.currency.iso_code, value2.currency.iso_code
    assert_equal value2.currency.iso_code, value3.currency.iso_code
    assert_equal value3.currency.iso_code, value4.currency.iso_code
  end

  test "equality tests amount and currency" do
    assert_equal Money.new(1000), Money.new(1000)
    assert_not_equal Money.new(1000), Money.new(1001)
    assert_not_equal Money.new(1000, :usd), Money.new(1000, :eur)
  end

  test "can compare with zero Numeric" do
    assert_equal Money.new(0), 0
    assert_raises(TypeError) { Money.new(1) == 1 }
  end

  test "can negate" do
    assert_equal (-Money.new(1000)), Money.new(-1000)
  end

  test "can use comparison operators" do
    assert_operator Money.new(1000), :>, Money.new(999)
    assert_operator Money.new(1000), :>=, Money.new(1000)
    assert_operator Money.new(1000), :<, Money.new(1001)
    assert_operator Money.new(1000), :<=, Money.new(1000)
  end

  test "can add and subtract" do
    assert_equal Money.new(1000) + Money.new(1000), Money.new(2000)
    assert_equal Money.new(1000) + 1000, Money.new(2000)
    assert_equal Money.new(1000) - Money.new(1000), Money.new(0)
    assert_equal Money.new(1000) - 1000, Money.new(0)
  end

  test "can multiply" do
    assert_equal Money.new(1000) * 2, Money.new(2000)
    assert_raises(TypeError) { Money.new(1000) * Money.new(2) }
  end

  test "can divide" do
    assert_equal Money.new(1000) / 2, Money.new(500)
    assert_equal Money.new(1000) / Money.new(500), 2
    assert_raise(TypeError) { 1000 / Money.new(2) }
  end

  test "operator order does not matter" do
    assert_equal Money.new(1000) + 1000, 1000 + Money.new(1000)
    assert_equal Money.new(1000) - 1000, 1000 - Money.new(1000)
    assert_equal Money.new(1000) * 2, 2 * Money.new(1000)
  end

  test "can get absolute value" do
    assert_equal Money.new(1000).abs, Money.new(1000)
    assert_equal Money.new(-1000).abs, Money.new(1000)
  end

  test "can test if zero" do
    assert Money.new(0).zero?
    assert_not Money.new(1000).zero?
  end

  test "can test if negative" do
    assert Money.new(-1000).negative?
    assert_not Money.new(1000).negative?
  end

  test "can test if positive" do
    assert Money.new(1000).positive?
    assert_not Money.new(-1000).positive?
  end

  test "can format" do
    assert_equal "$1,000.90", Money.new(1000.899, :usd).to_s
    assert_equal "€1,000.12", Money.new(1000.12, :eur).to_s
    assert_equal "€ 1.000,12", Money.new(1000.12, :eur).format(locale: :nl)
  end

  test "formats INR with lakh and crore grouping" do
    assert_equal "₹1,23,45,678.90", Money.new(12345678.9, "INR").format
    assert_equal "₹12,34,567.00", Money.new(1234567, "INR").format
    assert_equal "₹1,00,000.00", Money.new(100000, "INR").format
    assert_equal "₹45,600.00", Money.new(45600, "INR").format
    assert_equal "₹950.00", Money.new(950, "INR").format
    assert_equal "-₹1,23,456.00", Money.new(-123456, "INR").format
  end

  test "USD formatting is unchanged by Indian grouping" do
    assert_equal "$12,345,678.90", Money.new(12345678.9, "USD").format
  end

  test "defaults to INR" do
    assert_equal "INR", Money.new(100).currency.iso_code
  end

  test "formats compact INR" do
    assert_equal "₹950", Money.new(950, "INR").format_compact
    assert_equal "₹45.6K", Money.new(45600, "INR").format_compact
    assert_equal "₹45K", Money.new(45000, "INR").format_compact
    assert_equal "₹12.35 L", Money.new(1234567, "INR").format_compact
    assert_equal "₹1.23 Cr", Money.new(12345678.9, "INR").format_compact
    assert_equal "₹1.20 Cr", Money.new(12000000, "INR").format_compact
    assert_equal "-₹45.6K", Money.new(-45600, "INR").format_compact
  end

  test "formats compact for other currencies with K M B" do
    assert_equal "$950", Money.new(950, "USD").format_compact
    assert_equal "$45.6K", Money.new(45600, "USD").format_compact
    assert_equal "$1.23M", Money.new(1234567, "USD").format_compact
    assert_equal "$1.50B", Money.new(1500000000, "USD").format_compact
  end

  test "compact format moves to the next unit when rounding reaches it" do
    assert_equal "$1.00M", Money.new(BigDecimal("999999.999"), "USD").format_compact
    assert_equal "$1.00M", Money.new(1_000_000, "USD").format_compact
    assert_equal "$999.9K", Money.new(999_900, "USD").format_compact
    assert_equal "$1K", Money.new(BigDecimal("999.5"), "USD").format_compact
    assert_equal "$1.00B", Money.new(BigDecimal("999999999.9"), "USD").format_compact
    assert_equal "-$1.00M", Money.new(BigDecimal("-999999.999"), "USD").format_compact

    assert_equal "₹1.00 L", Money.new(BigDecimal("99999.5"), "INR").format_compact
    assert_equal "₹1.00 Cr", Money.new(BigDecimal("9999999.5"), "INR").format_compact
    assert_equal "₹99.99 L", Money.new(BigDecimal("9999000"), "INR").format_compact
    assert_equal "₹99.9K", Money.new(BigDecimal("99940"), "INR").format_compact
    assert_equal "₹1K", Money.new(BigDecimal("999.5"), "INR").format_compact
    assert_equal "₹999", Money.new(BigDecimal("999.4"), "INR").format_compact
  end

  test "converts currency when rate available" do
    ExchangeRate.expects(:find_or_fetch_rate).returns(OpenStruct.new(rate: 1.2))

    assert_equal Money.new(1000).exchange_to(:eur), Money.new(1000 * 1.2, :eur)
  end

  test "raises when no conversion rate available and no fallback rate provided" do
    ExchangeRate.expects(:find_or_fetch_rate).returns(nil)

    assert_raises Money::ConversionError do
      Money.new(1000).exchange_to(:jpy)
    end
  end

  test "converts currency with a fallback rate" do
    ExchangeRate.expects(:find_or_fetch_rate).returns(nil).twice

    assert_equal 0, Money.new(1000).exchange_to(:jpy, fallback_rate: 0)
    assert_equal Money.new(1000, :jpy), Money.new(1000, :usd).exchange_to(:jpy, fallback_rate: 1)
  end
end
