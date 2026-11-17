require "test_helper"

class HouseholdMemberTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  def build(attrs = {})
    @family.household_members.new({ name: "Rahul Sharma", relationship: "self", residency_status: "nri" }.merge(attrs))
  end

  test "residency is required and has no default" do
    member = @family.household_members.new(name: "Asha", relationship: "spouse")

    assert_nil member.residency_status
    assert_not member.valid?
    assert_includes member.errors[:residency_status].join, "Resident or NRI"
    assert_nil HouseholdMember.column_for_attribute(:residency_status).default
  end

  test "rejects an unknown residency status" do
    assert_not build(residency_status: "citizen").valid?
  end

  test "an NRI starts at a 30 percent slab rate, a resident is asked for theirs" do
    assert_equal BigDecimal("30"), build.tap(&:valid?).slab_rate
    assert_nil build(relationship: "spouse", residency_status: "resident").tap(&:valid?).slab_rate
  end

  test "an explicit slab rate is kept" do
    assert_equal BigDecimal("20"), build(slab_rate: 20).tap(&:valid?).slab_rate
  end

  test "only one member can be you" do
    build.save!

    assert_not build(name: "Someone else").valid?
    assert build(name: "Asha", relationship: "spouse", residency_status: "resident").valid?
  end

  test "pan last four must be four characters" do
    assert_not build(pan_last4: "12").valid?
    assert_equal "234F", build(pan_last4: "234f").tap(&:valid?).pan_last4
  end

  test "age uses the date of birth" do
    member = build(date_of_birth: Date.new(1990, 6, 15))

    assert_equal 36, member.age(on: Date.new(2026, 6, 15))
    assert_equal 35, member.age(on: Date.new(2026, 6, 14))
    assert_nil build.age
  end

  test "a retirement goal takes its age from the member's date of birth" do
    member = build(date_of_birth: Date.current.prev_year(40) - 10.days)
    member.save!

    goal = @family.goals.create!(
      name: "Retire", kind: "retirement", currency: "INR", household_member: member, current_age: 20, retirement_age: 60,
      life_expectancy: 85, monthly_expenses_today: 50_000, post_retirement_return: 7
    )

    assert_equal 40, goal.current_age
  end

  test "removing a member makes their accounts joint" do
    member = build.tap(&:save!)
    account = @family.accounts.create!(name: "NRE", balance: 0, currency: "INR", accountable: Depository.new, subtype: "nre", household_member: member)

    member.destroy!

    assert_nil account.reload.household_member_id
    assert_equal "Joint / household", account.owner_name
  end

  test "an account cannot belong to another family's member" do
    other = families(:empty).household_members.create!(name: "X", relationship: "self", residency_status: "resident")
    account = @family.accounts.new(name: "A", balance: 0, currency: "INR", accountable: Depository.new, household_member: other)

    assert_not account.valid?
  end

  test "an NRI's accounts carry residency warnings" do
    nri = build.tap(&:save!)
    ppf = @family.accounts.create!(name: "PPF", balance: 0, currency: "INR", accountable: ProvidentFund.new, subtype: "ppf", household_member: nri)
    savings = @family.accounts.create!(name: "Savings", balance: 0, currency: "INR", accountable: Depository.new, subtype: "savings", household_member: nri)
    nre = @family.accounts.create!(name: "NRE", balance: 0, currency: "INR", accountable: Depository.new, subtype: "nre", household_member: nri)

    assert_match(/cannot be extended/, ppf.residency_warnings.first)
    assert_match(/NRE or NRO/, savings.residency_warnings.first)
    assert_empty nre.residency_warnings

    nri.update!(residency_status: "resident")
    assert_empty ppf.reload.residency_warnings
  end
end
