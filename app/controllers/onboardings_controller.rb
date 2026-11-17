class OnboardingsController < ApplicationController
  layout "wizard"

  before_action :set_user
  before_action :load_invitation

  def show
  end

  def preferences
  end

  def household
    @members = onboarding_rows_from_family
  end

  # Row 0 is you and is required; rows 1 and 2 are optional (a spouse, a parent...). Rows without a name are ignored.
  def save_household
    @members = onboarding_rows_from_params
    built = @members.filter_map { |row| row[:name].present? ? Current.family.household_members.new(row.except(:index)) : nil }

    if built.empty?
      @error = "Add at least yourself, or skip this step."
      return render :household, status: :unprocessable_entity
    end

    HouseholdMember.transaction do
      built.each(&:save!)
      Current.user.update!(household_member: built.find(&:myself?)) if built.any?(&:myself?)
    end

    redirect_to goals_onboarding_path
  rescue ActiveRecord::RecordInvalid => e
    @error = e.record.errors.full_messages.to_sentence
    render :household, status: :unprocessable_entity
  end

  def trial
  end

  private
    ONBOARDING_ROWS = 3

    def onboarding_rows_from_family
      existing = Current.family.household_members.ordered.to_a.first(ONBOARDING_ROWS)

      Array.new(ONBOARDING_ROWS) do |index|
        member = existing[index]
        {
          index: index,
          name: member&.name || (index.zero? ? Current.user.display_name : nil),
          relationship: member&.relationship || [ "self", "spouse", "child" ][index],
          residency_status: member&.residency_status
        }
      end
    end

    def onboarding_rows_from_params
      Array.new(ONBOARDING_ROWS) do |index|
        row = params.dig(:members, index.to_s)&.permit(:name, :relationship, :residency_status)&.to_h || {}
        { index: index, name: row["name"].to_s.squish, relationship: index.zero? ? "self" : row["relationship"].presence || "spouse",
          residency_status: row["residency_status"].presence }
      end
    end

    def set_user
      @user = Current.user
    end

    def load_invitation
      @invitation = Current.family.invitations.accepted.find_by(email: Current.user.email)
    end
end
