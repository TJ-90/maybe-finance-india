require "test_helper"

class InsurancePolicyTest < ActiveSupport::TestCase
  setup do
    @policy = insurance_policies(:term)
  end

  test "policy number is encrypted at rest" do
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT policy_number FROM insurance_policies WHERE id = '#{@policy.id}'"
    )

    assert_equal "TERM-0001-2345", @policy.policy_number
    assert_not_includes raw, "TERM-0001-2345"
  end

  test "masks the policy number for display" do
    assert_equal "XXXX 2345", @policy.masked_policy_number
    assert_nil InsurancePolicy.new.masked_policy_number
  end

  test "money fields use the policy currency" do
    assert_equal Money.new(10_000_000, "INR"), @policy.sum_assured_money
    assert_equal Money.new(24_000, "INR"), @policy.premium_money
  end

  test "finds premiums due in the next 30 days, soonest first" do
    due = families(:dylan_family).insurance_policies.premium_due_within(30.days)

    assert_equal [ @policy ], due.to_a
    assert_empty families(:dylan_family).insurance_policies.premium_due_within(5.days)
  end

  test "ignores premiums already past" do
    @policy.update!(next_premium_due_on: 2.days.ago.to_date)

    assert_empty families(:dylan_family).insurance_policies.premium_due_within(30.days)
  end

  test "advancing the premium moves the due date by one period" do
    @policy.update!(premium_frequency: "quarterly", next_premium_due_on: Date.current + 5.days)

    @policy.advance_premium_due!

    assert_equal (Date.current + 5.days) >> 3, @policy.next_premium_due_on
  end

  test "advancing a single-premium policy clears the due date" do
    @policy.update!(premium_frequency: "single")

    @policy.advance_premium_due!

    assert_nil @policy.next_premium_due_on
  end

  test "requires an insurer and a valid kind" do
    policy = InsurancePolicy.new(family: families(:dylan_family), currency: "INR", kind: "pet")

    assert_not policy.valid?
    assert policy.errors[:insurer].any?
    assert policy.errors[:kind].any?
  end

  test "end date cannot precede start date" do
    @policy.end_date = @policy.start_date - 1.day

    assert_not @policy.valid?
  end

  test "accepts PDF documents and rejects other types" do
    @policy.documents.attach(io: StringIO.new("%PDF-1.4"), filename: "policy.pdf", content_type: "application/pdf")
    assert @policy.valid?

    @policy.documents.attach(io: StringIO.new("MZ"), filename: "virus.exe", content_type: "application/x-msdownload")
    assert_not @policy.valid?
  end
end
