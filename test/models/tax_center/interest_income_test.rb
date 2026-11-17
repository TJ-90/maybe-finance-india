require "test_helper"

class TaxCenter::InterestIncomeTest < ActiveSupport::TestCase
  include TaxTestHelper

  setup do
    @family = inr_family
    @nri = @family.household_members.create!(name: "Rahul", relationship: "self", residency_status: "nri")
    @resident = @family.household_members.create!(name: "Asha", relationship: "spouse", residency_status: "resident")
  end

  def depository(name, subtype, member)
    @family.accounts.create!(name: name, balance: 0, currency: "INR", accountable: Depository.new, subtype: subtype, household_member: member)
  end

  def credit_interest(account, amount, date)
    account.entries.create!(name: "Interest credit", date: date, amount: -amount, currency: "INR", entryable: Transaction.new(kind: "standard"))
  end

  def interest(member, accounts)
    TaxCenter::InterestIncome.new(
      family: @family, accounts: accounts, financial_year_start: Date.new(2026, 4, 1), residency: TaxCenter::Residency.new(member: member)
    )
  end

  test "NRE interest is exempt for an NRI and NRO interest is taxable with an estimated TDS" do
    nre = depository("NRE", "nre", @nri)
    nro = depository("NRO", "nro", @nri)
    credit_interest nre, 6_000, Date.new(2026, 6, 30)
    credit_interest nro, 2_000, Date.new(2026, 6, 30)
    credit_interest nro, 9_999, Date.new(2026, 3, 31) # previous financial year

    result = interest(@nri, [ nre, nro ])

    assert_equal BigDecimal("6000"), result.exempt_total
    assert_equal BigDecimal("2000"), result.taxable_total
    assert_equal BigDecimal("624"), result.rows.find { |row| row.account == nro }.tds # 30% plus 4% cess
    assert result.notes.first.include?("30%")
  end

  test "a resident's savings interest is taxable and the TDS threshold note is shown" do
    savings = depository("Savings", "savings", @resident)
    credit_interest savings, 12_000, Date.new(2026, 5, 1)

    result = interest(@resident, [ savings ])

    assert_equal BigDecimal("12000"), result.taxable_total
    assert_equal 0, result.exempt_total
    assert_match(/50,000/, result.notes.first)
  end

  test "NRE interest of a resident is treated as taxable" do
    nre = depository("NRE", "nre", @resident)
    credit_interest nre, 1_000, Date.new(2026, 5, 1)

    assert_equal BigDecimal("1000"), interest(@resident, [ nre ]).taxable_total
  end

  test "provident fund interest comes from generated entries and is exempt" do
    ppf = @family.accounts.create!(name: "PPF", balance: 0, currency: "INR", accountable: ProvidentFund.new, subtype: "ppf", household_member: @resident)
    ppf.replace_generated_entries!(ProvidentFund::InterestPoster::SOURCE, [
      { date: Date.new(2027, 3, 31), name: "PPF interest FY 2026-27", amount: -24_000, entryable: Transaction.new(kind: "one_time") },
      { date: Date.new(2026, 3, 31), name: "PPF interest FY 2025-26", amount: -20_000, entryable: Transaction.new(kind: "one_time") }
    ])

    result = interest(@resident, [ ppf ])

    assert_equal BigDecimal("24000"), result.exempt_total
    assert_equal 0, result.taxable_total
  end

  test "payout FD interest is taxable and a cumulative FD accrues inside the deposit" do
    payout = @family.accounts.create!(
      name: "Payout FD", balance: 0, currency: "INR", subtype: "fd", household_member: @resident,
      accountable: FixedDeposit.new(interest_rate: 7, compounding: "quarterly", payout: "quarterly", principal: 100_000, start_date: Date.new(2026, 4, 1), maturity_date: Date.new(2028, 4, 1))
    )
    payout.replace_generated_entries!(FixedDeposit::Accruer::PAYOUT_SOURCE, [
      { date: Date.new(2026, 7, 1), name: "Interest payout", amount: -1_750, entryable: Transaction.new(kind: "standard") }
    ])
    cumulative = @family.accounts.create!(
      name: "Cumulative FD", balance: 0, currency: "INR", subtype: "fd", household_member: @resident,
      accountable: FixedDeposit.new(interest_rate: 7, compounding: "quarterly", payout: "cumulative", principal: 100_000, start_date: Date.new(2025, 4, 1), maturity_date: Date.new(2028, 4, 1))
    )

    result = interest(@resident, [ payout, cumulative ])

    assert_equal BigDecimal("1750"), result.rows.find { |row| row.account == payout }.amount
    # 7% quarterly compounded for a year: 107,186 - 100,000, then a further year of growth
    assert_in_delta 7_186, cumulative.accountable.interest_accrued_between(Date.new(2025, 4, 1), Date.new(2026, 4, 1)), 2
    assert_in_delta 7_686, result.rows.find { |row| row.account == cumulative }.amount, 20
    assert_equal 0, result.exempt_total
  end
end
