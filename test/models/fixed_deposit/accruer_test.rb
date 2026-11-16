require "test_helper"

class FixedDeposit::AccruerTest < ActiveSupport::TestCase
  setup do
    @today = Date.new(2026, 7, 15)
  end

  def create_deposit(subtype: "fd", **terms)
    families(:empty).accounts.create_and_sync(
      name: "Deposit",
      balance: terms[:principal] || terms[:monthly_installment],
      currency: "INR",
      subtype: subtype,
      accountable_type: "FixedDeposit",
      accountable_attributes: {
        interest_rate: 7,
        compounding: "quarterly",
        payout: "cumulative",
        start_date: Date.new(2026, 1, 1),
        maturity_date: Date.new(2027, 1, 1)
      }.merge(terms)
    ).accountable
  end

  def accrue(fd)
    FixedDeposit::Accruer.new(fd, as_of: @today).accrue!
  end

  test "writes month-end valuations and one for today, marked as generated" do
    fd = create_deposit(principal: 100_000)

    accrue(fd)

    generated = fd.account.entries.generated.valuations.order(:date)
    expected_dates = (1..6).map { |m| Date.new(2026, m, 1).end_of_month } + [ @today ]

    assert_equal expected_dates, generated.map(&:date)
    assert generated.all? { |entry| entry.generated_by == FixedDeposit::Accruer::VALUE_SOURCE }
    assert_equal fd.value_on(@today), generated.last.amount
  end

  test "running the accruer repeatedly never duplicates entries" do
    fd = create_deposit(principal: 100_000)

    accrue(fd)
    assert_no_difference -> { fd.account.entries.count } do
      3.times { accrue(fd) }
    end
  end

  test "user-entered valuations are never touched or duplicated" do
    fd = create_deposit(principal: 100_000)
    manual = fd.account.entries.create!(
      date: Date.new(2026, 3, 31), name: "Bank statement value", amount: 103_000, currency: "INR",
      entryable: Valuation.new(kind: "reconciliation")
    )

    2.times { accrue(fd) }

    assert_equal 103_000, manual.reload.amount
    assert_nil manual.generated_by
    assert_equal 1, fd.account.entries.valuations.where(date: Date.new(2026, 3, 31)).count
    assert_equal 1, fd.account.entries.valuations.where(date: Date.new(2026, 1, 1)).count # the opening anchor
  end

  test "a generated entry the user edited becomes theirs and is kept" do
    fd = create_deposit(principal: 100_000)
    accrue(fd)

    entry = fd.account.entries.generated.valuations.find_by(date: Date.new(2026, 2, 28))
    entry.update!(amount: 101_111)
    assert entry.reload.generated_user_edited?

    accrue(fd)

    assert_equal 101_111, entry.reload.amount
    assert_equal 1, fd.account.entries.valuations.where(date: Date.new(2026, 2, 28)).count
  end

  test "regenerates with new values when the terms change" do
    fd = create_deposit(principal: 100_000)
    accrue(fd)
    before = fd.account.entries.generated.valuations.find_by(date: @today).amount

    fd.update_columns(interest_rate: 9)
    accrue(fd)

    assert_operator fd.account.entries.generated.valuations.find_by(date: @today).amount, :>, before
  end

  test "stops at maturity and freezes the value" do
    fd = create_deposit(principal: 100_000, start_date: Date.new(2025, 1, 1), maturity_date: Date.new(2026, 1, 1))

    accrue(fd)

    values = fd.account.entries.generated.valuations.order(:date)
    assert_includes values.map(&:date), Date.new(2026, 1, 1)
    assert_equal fd.maturity_value, values.last.amount
    assert_equal @today, values.last.date
  end

  test "payout FD writes interest income transactions and no valuations" do
    fd = create_deposit(principal: 120_000, payout: "monthly", interest_rate: 6)

    2.times { accrue(fd) }

    payouts = fd.account.entries.generated.where(entryable_type: "Transaction").order(:date)

    assert_equal 6, payouts.count # Feb 1 .. Jul 1
    assert_equal Date.new(2026, 2, 1), payouts.first.date
    assert payouts.all? { |entry| entry.amount == -600 }
    assert_equal 0, fd.account.entries.generated.valuations.count
  end

  test "payout interest uses the Interest category when the family has one" do
    category = families(:empty).categories.create!(name: "Interest", color: "#12B76A", lucide_icon: "percent")
    fd = create_deposit(principal: 120_000, payout: "quarterly", interest_rate: 6)

    accrue(fd)

    assert_equal category, fd.account.entries.generated.where(entryable_type: "Transaction").first.transaction.category
  end

  test "syncing an account generates the entries and sets the balance from the accrued value" do
    fd = create_deposit(principal: 100_000, start_date: 6.months.ago.to_date, maturity_date: 6.months.from_now.to_date)
    account = fd.account

    Account::MarketDataImporter.any_instance.stubs(:import_all)
    2.times { Account::Syncer.new(account).perform_sync(Sync.new) }

    assert account.entries.generated.valuations.any?
    assert_equal fd.value_on(Date.current), account.reload.balance
    assert_equal account.entries.valuations.count, account.entries.valuations.distinct.count(:date)
  end
end
