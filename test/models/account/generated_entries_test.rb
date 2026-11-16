require "test_helper"

class Account::GeneratedEntriesTest < ActiveSupport::TestCase
  setup do
    @account = families(:empty).accounts.create!(
      name: "Gold",
      balance: 1000,
      currency: "INR",
      accountable: PreciousMetal.new(weight_grams: 10, purity: "24k", form: "coins")
    )
    @account.set_opening_anchor_balance(balance: 1000, date: Date.new(2026, 1, 1))
  end

  def valuation_spec(date, amount)
    { date: date, name: "Generated", amount: amount, entryable: Valuation.new(kind: "reconciliation") }
  end

  test "replacing is idempotent" do
    specs = [ valuation_spec(Date.new(2026, 1, 31), 1100), valuation_spec(Date.new(2026, 2, 28), 1200) ]

    @account.replace_generated_entries!("test_source", specs)

    assert_no_difference -> { @account.entries.count } do
      @account.replace_generated_entries!("test_source", specs)
    end
  end

  test "replacing drops generated entries that are no longer wanted" do
    @account.replace_generated_entries!("test_source", [ valuation_spec(Date.new(2026, 1, 31), 1100), valuation_spec(Date.new(2026, 2, 28), 1200) ])
    @account.replace_generated_entries!("test_source", [ valuation_spec(Date.new(2026, 1, 31), 1150) ])

    generated = @account.entries.generated
    assert_equal [ Date.new(2026, 1, 31) ], generated.map(&:date)
    assert_equal 1150, generated.first.amount
  end

  test "entries from other sources and user entries are untouched" do
    other = @account.entries.create!(
      date: Date.new(2026, 3, 31), name: "Other", amount: 1300, currency: "INR",
      generated_by: "other_source", entryable: Valuation.new(kind: "reconciliation")
    )

    @account.replace_generated_entries!("test_source", [ valuation_spec(Date.new(2026, 1, 31), 1100) ])
    @account.replace_generated_entries!("test_source", [])

    assert Entry.exists?(other.id)
    assert Entry.exists?(@account.entries.valuations.find_by(date: Date.new(2026, 1, 1)).id) # opening anchor
  end

  test "never writes a valuation on a date that already has one" do
    @account.entries.create!(
      date: Date.new(2026, 1, 31), name: "Mine", amount: 999, currency: "INR",
      entryable: Valuation.new(kind: "reconciliation")
    )

    @account.replace_generated_entries!("test_source", [ valuation_spec(Date.new(2026, 1, 31), 1100) ])

    assert_equal 0, @account.entries.generated.count
    assert_equal 999, @account.entries.valuations.find_by(date: Date.new(2026, 1, 31)).amount
  end

  test "editing a generated entry makes it user-owned" do
    @account.replace_generated_entries!("test_source", [ valuation_spec(Date.new(2026, 1, 31), 1100) ])
    entry = @account.entries.generated.sole

    assert entry.auto_generated?

    entry.update!(amount: 1111)

    assert entry.reload.generated_user_edited?
    assert_not entry.auto_generated?
    assert_equal 0, @account.entries.auto_generated.count
  end

  test "touching only timestamps does not claim the entry for the user" do
    @account.replace_generated_entries!("test_source", [ valuation_spec(Date.new(2026, 1, 31), 1100) ])
    entry = @account.entries.generated.sole

    entry.touch

    assert_not entry.reload.generated_user_edited?
  end
end
