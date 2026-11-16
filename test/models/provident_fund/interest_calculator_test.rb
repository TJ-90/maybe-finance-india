require "test_helper"

class ProvidentFund::InterestCalculatorTest < ActiveSupport::TestCase
  def create_fund(subtype:, balance: 100_000, opened_on: Date.new(2025, 4, 1), **attrs)
    families(:empty).accounts.create_and_sync(
      name: "Fund",
      balance: balance,
      currency: "INR",
      subtype: subtype,
      accountable_type: "ProvidentFund",
      accountable_attributes: { opened_on: opened_on }.merge(attrs)
    ).accountable
  end

  # 10,000 deposited on the 20th of every month from May 2025 to March 2026
  def deposit_monthly_on_the_20th(fund)
    (0..10).each do |i|
      fund.account.entries.create!(
        date: Date.new(2025, 5, 20) >> i,
        name: "Contribution",
        amount: -10_000,
        currency: "INR",
        entryable: Transaction.new(kind: "funds_movement")
      )
    end
  end

  test "annual interest on a flat balance is balance x rate" do
    interest = ProvidentFund::InterestCalculator.annual_interest(
      method: :balance_on_fifth,
      fy_start_year: 2025,
      balance_on: ->(_date) { BigDecimal("100000") },
      rate_on: ->(_date) { BigDecimal("7.1") }
    )

    assert_equal 7100, interest
  end

  test "PPF interest uses the balance on the 5th of each month" do
    fund = create_fund(subtype: "ppf", interest_rate: 7.1)
    deposit_monthly_on_the_20th(fund)

    credits = ProvidentFund::InterestCalculator.new(fund, as_of: Date.new(2026, 3, 31)).credits

    # Balances on the 5th, in thousands: Apr 100, May 100, Jun 110 ... Mar 200  => sum 1,750,000
    # 1,750,000 x 7.1% / 12 = 10,354.17
    assert_equal 1, credits.size
    assert_equal Date.new(2026, 3, 31), credits.first.date
    assert_equal "2025-26", credits.first.financial_year
    assert_equal 10_354, credits.first.amount
  end

  test "EPF interest uses the month-end running balance" do
    fund = create_fund(subtype: "epf", interest_rate: 8.25)
    deposit_monthly_on_the_20th(fund)

    credits = ProvidentFund::InterestCalculator.new(fund, as_of: Date.new(2026, 3, 31)).credits

    # Month-end balances, in thousands: Apr 100, May 110 ... Mar 210 => sum 1,860,000
    # 1,860,000 x 8.25% / 12 = 12,787.50, rounded to the nearest rupee
    assert_equal 12_788, credits.first.amount
  end

  test "interest credited in one year earns interest the next year" do
    fund = create_fund(subtype: "epf", interest_rate: 8.25)
    deposit_monthly_on_the_20th(fund)

    credits = ProvidentFund::InterestCalculator.new(fund, as_of: Date.new(2027, 3, 31)).credits

    # Closing balance after FY 2025-26: 210,000 + 12,788 = 222,788, flat all year
    # 222,788 x 8.25% = 18,380.01
    assert_equal [ 12_788, 18_380 ], credits.map(&:amount)
    assert_equal [ Date.new(2026, 3, 31), Date.new(2027, 3, 31) ], credits.map(&:date)
  end

  test "interest is only credited once the financial year has ended" do
    fund = create_fund(subtype: "ppf", interest_rate: 7.1)

    assert_empty ProvidentFund::InterestCalculator.new(fund, as_of: Date.new(2026, 3, 30)).credits
    assert_equal 1, ProvidentFund::InterestCalculator.new(fund, as_of: Date.new(2026, 3, 31)).credits.size
  end

  test "interest only runs from the opening date" do
    fund = create_fund(subtype: "ppf", interest_rate: 7.1, opened_on: Date.new(2025, 10, 1))

    credits = ProvidentFund::InterestCalculator.new(fund, as_of: Date.new(2026, 3, 31)).credits

    # Oct..Mar = 6 months on 100,000
    assert_equal 3_550, credits.first.amount
  end

  test "falls back to the configured default rate when there is no override" do
    fund = create_fund(subtype: "ppf")

    credits = ProvidentFund::InterestCalculator.new(fund, as_of: Date.new(2026, 3, 31)).credits

    assert_equal 7_100, credits.first.amount # PPF is 7.1% in config/india_small_savings_rates.yml
  end

  test "a user valuation resets the running balance" do
    fund = create_fund(subtype: "ppf", interest_rate: 7.1)
    fund.account.entries.create!(
      date: Date.new(2025, 9, 15), name: "Passbook balance", amount: 200_000, currency: "INR",
      entryable: Valuation.new(kind: "reconciliation")
    )

    credits = ProvidentFund::InterestCalculator.new(fund, as_of: Date.new(2026, 3, 31)).credits

    # Apr..Sep 5th at 100,000 (6 months), Oct..Mar at 200,000 (6 months) = 1,800,000 x 7.1% / 12
    assert_equal 10_650, credits.first.amount
  end

  test "no interest after the maturity date" do
    fund = create_fund(subtype: "ssy", interest_rate: 8.2, maturity_date: Date.new(2025, 9, 30))

    credits = ProvidentFund::InterestCalculator.new(fund, as_of: Date.new(2026, 3, 31)).credits

    # Apr..Sep only: 6 months on 100,000 at 8.2%
    assert_equal 4_100, credits.first.amount
  end
end
