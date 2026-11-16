require "test_helper"

class ProvidentFund::InterestPosterTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 11, 16, 12)

    @fund = families(:empty).accounts.create_and_sync(
      name: "EPF",
      balance: 100_000,
      currency: "INR",
      subtype: "epf",
      accountable_type: "ProvidentFund",
      accountable_attributes: { opened_on: Date.new(2025, 4, 1), interest_rate: 8.25 }
    ).accountable
    @account = @fund.account
  end

  def post
    ProvidentFund::InterestPoster.new(@fund).post!
  end

  test "posts one interest transaction per financial year, marked as generated" do
    post

    entry = @account.entries.generated.sole

    assert_equal Date.new(2026, 3, 31), entry.date
    assert_equal -8_250, entry.amount # 100,000 flat x 8.25%; negative = inflow
    assert_equal "EPF interest FY 2025-26", entry.name
    assert_equal ProvidentFund::InterestPoster::SOURCE, entry.generated_by
    assert entry.transaction?
    assert entry.transaction.one_time?
  end

  test "posting again never duplicates the entry" do
    post

    assert_no_difference -> { @account.entries.count } do
      3.times { post }
    end
  end

  test "an interest entry the user edited is kept and not generated again" do
    post
    entry = @account.entries.generated.sole
    entry.update!(amount: -9_000)

    post

    assert_equal 1, @account.entries.where(date: Date.new(2026, 3, 31), entryable_type: "Transaction").count
    assert_equal -9_000, entry.reload.amount
    assert entry.generated_user_edited?
  end

  test "user transactions are left alone" do
    mine = @account.entries.create!(
      date: Date.new(2026, 3, 31), name: "My own entry", amount: -500, currency: "INR",
      entryable: Transaction.new(kind: "standard")
    )

    2.times { post }

    assert_equal -500, mine.reload.amount
    assert_nil mine.generated_by
  end

  test "syncing credits the interest into the balance" do
    Account::MarketDataImporter.any_instance.stubs(:import_all)

    2.times { Account::Syncer.new(@account).perform_sync(Sync.new) }

    assert_equal 108_250, @account.reload.balance
    assert_equal 1, @account.entries.generated.count
  end
end
