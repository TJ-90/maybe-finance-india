require "test_helper"

class FixedDepositTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  test "FD of 1,00,000 at 7% compounded quarterly is worth 1,07,186 after one year" do
    fd = create_deposit(principal: 100_000)

    assert_in_delta 107_186, fd.value_on(Date.new(2027, 1, 1)), 1
    assert_in_delta 107_186, fd.maturity_value, 1
  end

  test "value at the start date is the principal and before it is zero" do
    fd = create_deposit(principal: 100_000)

    assert_equal 100_000, fd.value_on(Date.new(2026, 1, 1))
    assert_equal 0, fd.value_on(Date.new(2025, 12, 31))
  end

  test "FD grows between start and maturity and freezes after maturity" do
    fd = create_deposit(principal: 100_000)

    half_way = fd.value_on(Date.new(2026, 7, 1))
    assert_operator half_way, :>, 100_000
    assert_operator half_way, :<, fd.maturity_value
    assert_equal fd.maturity_value, fd.value_on(Date.new(2030, 1, 1))
  end

  test "auto-renewing FD keeps compounding after maturity" do
    fd = create_deposit(principal: 100_000, auto_renew: true)

    assert_in_delta 100_000 * 1.0175**8, fd.value_on(Date.new(2028, 1, 1)), 1
  end

  test "compounding frequency changes the maturity value" do
    monthly = create_deposit(principal: 100_000, compounding: "monthly")
    yearly = create_deposit(principal: 100_000, compounding: "yearly")
    simple = create_deposit(principal: 100_000, compounding: "simple")

    assert_in_delta 100_000 * (1 + 0.07 / 12)**12, monthly.maturity_value, 1
    assert_in_delta 107_000, yearly.maturity_value, 1
    assert_in_delta 107_000, simple.maturity_value, 1
  end

  test "RD of 5,000 a month at 6.5% for 12 months matures at about 62,144" do
    rd = create_deposit(subtype: "rd", monthly_installment: 5_000, interest_rate: 6.5)

    assert_in_delta 62_144, rd.maturity_value, 1
    assert_equal 12, rd.tenure_months
  end

  test "RD value on the start date is the first installment" do
    rd = create_deposit(subtype: "rd", monthly_installment: 5_000, interest_rate: 6.5)

    assert_equal 5_000, rd.value_on(Date.new(2026, 1, 1))
    assert_equal 5_000, rd.account.opening_anchor_balance
  end

  test "payout FD keeps the principal flat and pays simple interest each period" do
    fd = create_deposit(principal: 120_000, payout: "monthly", interest_rate: 6)

    assert_equal 120_000, fd.value_on(Date.new(2026, 8, 1))
    assert_equal 600, fd.payout_amount # 1,20,000 x 6% / 12
  end

  test "creating the account anchors the opening balance on the start date" do
    fd = create_deposit(principal: 100_000, start_date: Date.new(2025, 6, 15), maturity_date: Date.new(2026, 6, 15))

    assert_equal Date.new(2025, 6, 15), fd.account.opening_anchor_date
    assert_equal 100_000, fd.account.opening_anchor_balance
  end

  test "changing the principal moves the opening anchor and schedules a sync" do
    fd = create_deposit(principal: 100_000)
    fd.account.syncs.destroy_all # creating the account already queued a sync

    assert_enqueued_with(job: SyncJob) do
      fd.update!(principal: 150_000)
    end

    assert_equal 150_000, fd.account.reload.opening_anchor_balance
  end

  test "requires a rate, dates and a principal or installment" do
    fd = FixedDeposit.new(interest_rate: 7, compounding: "quarterly", payout: "cumulative")

    assert_not fd.valid?
    assert fd.errors[:start_date].any?
    assert fd.errors[:maturity_date].any?
    assert fd.errors[:principal].any?
  end

  test "maturity must be after start" do
    fd = FixedDeposit.new(
      interest_rate: 7, compounding: "quarterly", payout: "cumulative", principal: 1000,
      start_date: Date.new(2026, 1, 1), maturity_date: Date.new(2026, 1, 1)
    )

    assert_not fd.valid?
    assert fd.errors[:maturity_date].any?
  end
end
