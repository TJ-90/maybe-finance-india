class Settings::HouseholdMembersController < ApplicationController
  before_action :set_member, only: %i[edit update destroy]

  def index
    @members = Current.family.household_members.ordered.includes(:accounts)

    render layout: "settings"
  end

  def new
    # Residency is deliberately not preselected: it has to be chosen
    @member = Current.family.household_members.new(relationship: first_relationship)
  end

  def create
    @member = Current.family.household_members.new(member_params)

    if @member.save
      link_current_user(@member)
      redirect_to settings_household_members_path, notice: "#{@member.name} added"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @member.update(member_params)
      link_current_user(@member)
      redirect_to settings_household_members_path, notice: "#{@member.name} updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Accounts and goals the person owned become Joint / household
  def destroy
    @member.destroy!
    redirect_to settings_household_members_path, notice: "#{@member.name} removed. Their accounts are now shown as joint."
  end

  private
    def set_member
      @member = Current.family.household_members.find(params[:id])
    end

    # "Myself" is the natural first choice until it has been taken
    def first_relationship
      Current.family.household_members.exists?(relationship: "self") ? "spouse" : "self"
    end

    def link_current_user(member)
      Current.user.update!(household_member: member) if params[:link_current_user] == "1"
    end

    def member_params
      params.require(:household_member).permit(
        :name, :relationship, :residency_status, :date_of_birth, :pan_last4, :slab_rate, :tax_regime
      )
    end
end
