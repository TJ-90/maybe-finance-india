require "test_helper"

class InsurancePoliciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @policy = insurance_policies(:term)
  end

  test "lists the family's policies without exposing the full policy number" do
    get insurance_policies_path

    assert_response :success
    assert_select "##{dom_id(@policy)}"
    assert_select "##{dom_id(insurance_policies(:health))}"
    assert_no_match "TERM-0001-2345", response.body
    assert_match "XXXX 2345", response.body
  end

  test "does not list another family's policies" do
    other = families(:empty).insurance_policies.create!(kind: "term", insurer: "Other Co", currency: "INR")

    get insurance_policies_path

    assert_select "##{dom_id(other)}", count: 0
  end

  test "shows new and edit forms" do
    get new_insurance_policy_path
    assert_response :success

    get edit_insurance_policy_path(@policy)
    assert_response :success
  end

  test "creates a policy with a document" do
    file = fixture_file_upload("profile_image.png", "image/png")

    assert_difference -> { InsurancePolicy.count } => 1 do
      post insurance_policies_path, params: {
        insurance_policy: {
          kind: "health",
          insurer: "Care Health",
          policy_number: "CARE-1111",
          insured_names: "Self",
          currency: "INR",
          sum_assured: 500_000,
          premium: 12_000,
          premium_frequency: "yearly",
          next_premium_due_on: 15.days.from_now.to_date,
          documents: [ file ]
        }
      }
    end

    assert_redirected_to insurance_policies_path

    created = InsurancePolicy.order(:created_at).last
    assert_equal @user.family, created.family
    assert_equal "CARE-1111", created.policy_number
    assert_equal 500_000, created.sum_assured
    assert_equal 1, created.documents.count
  end

  test "rejects an invalid policy" do
    assert_no_difference -> { InsurancePolicy.count } do
      post insurance_policies_path, params: { insurance_policy: { kind: "term", insurer: "", currency: "INR" } }
    end

    assert_response :unprocessable_entity
  end

  test "updates a policy and keeps existing documents when adding more" do
    @policy.documents.attach(io: StringIO.new("%PDF-1.4"), filename: "first.pdf", content_type: "application/pdf")

    patch insurance_policy_path(@policy), params: {
      insurance_policy: {
        premium: 25_000,
        documents: [ fixture_file_upload("profile_image.png", "image/png") ]
      }
    }

    assert_redirected_to insurance_policies_path
    assert_equal 25_000, @policy.reload.premium
    assert_equal 2, @policy.documents.count
  end

  test "marks the premium as paid" do
    due = @policy.next_premium_due_on

    patch mark_premium_paid_insurance_policy_path(@policy)

    assert_redirected_to insurance_policies_path
    assert_equal due >> 12, @policy.reload.next_premium_due_on
  end

  test "destroys a policy" do
    assert_difference -> { InsurancePolicy.count } => -1 do
      delete insurance_policy_path(@policy)
    end

    assert_redirected_to insurance_policies_path
  end

  test "cannot touch another family's policy" do
    other = families(:empty).insurance_policies.create!(kind: "term", insurer: "Other Co", currency: "INR")

    delete insurance_policy_path(other)

    assert_response :not_found
    assert InsurancePolicy.exists?(other.id)
  end
end
