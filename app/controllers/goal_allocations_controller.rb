class GoalAllocationsController < ApplicationController
  before_action :set_goal

  def create
    account_id, security_id = params.dig(:goal_allocation, :target).to_s.split("|", 2)
    account = Current.family.accounts.find_by(id: account_id)
    security = Security.find_by(id: security_id) if security_id.present?

    @allocation = @goal.goal_allocations.new(
      account: account,
      security: security,
      percentage: params.dig(:goal_allocation, :percentage)
    )

    if account && @allocation.save
      redirect_to goal_path(@goal), notice: "Allocation added"
    else
      message = account ? @allocation.errors.full_messages.to_sentence : "Choose an account"
      redirect_to goal_path(@goal), alert: message
    end
  end

  def destroy
    @goal.goal_allocations.find(params[:id]).destroy!
    redirect_to goal_path(@goal), notice: "Allocation removed"
  end

  private
    def set_goal
      @goal = Current.family.goals.find(params[:goal_id])
    end
end
