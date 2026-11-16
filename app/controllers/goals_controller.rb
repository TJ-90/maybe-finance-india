class GoalsController < ApplicationController
  before_action :set_goal, only: %i[show edit update destroy]

  def index
    @goals = Current.family.goals.includes(goal_allocations: %i[account security]).ordered
  end

  def show
    @projection = @goal.projection
    @rebalancer = @goal.rebalancer
    @allocation_options = allocation_options
  end

  def new
    @goal = Current.family.goals.new(
      currency: Current.family.currency,
      kind: Goal::KINDS.key?(params[:kind]) ? params[:kind] : "custom",
      target_date: 5.years.from_now.to_date
    )
    prefill_emergency_fund(@goal)
  end

  def create
    @goal = Current.family.goals.new(goal_params)

    if @goal.save
      redirect_to goal_path(@goal), notice: "Goal created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    prefill_emergency_fund(@goal)
  end

  def update
    if @goal.update(goal_params)
      redirect_to goal_path(@goal), notice: "Goal updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @goal.destroy!
    redirect_to goals_path, notice: "Goal deleted"
  end

  private
    def set_goal
      @goal = Current.family.goals.find(params[:id])
    end

    def goal_params
      params.require(:goal).permit(
        :name, :kind, :target_amount, :currency, :target_date, :inflation_rate,
        :expected_equity_return, :expected_debt_return, :monthly_sip, :sip_step_up_pct,
        :initial_equity_pct, :final_equity_pct, :glide_path_years, :notes,
        :current_age, :retirement_age, :life_expectancy, :monthly_expenses_today,
        :post_retirement_return
      )
    end

    # "Use my average expenses" reloads the form with the target filled in from the last six
    # months of spending. Nothing is saved until the form is submitted.
    def prefill_emergency_fund(goal)
      return unless params[:use_average_expenses].present? && goal.emergency_fund?

      months = params[:months].to_i
      months = Goal::DEFAULT_EMERGENCY_MONTHS unless months.between?(1, 60)
      @emergency_months = months

      goal.target_amount = goal.emergency_fund_target(months: months).amount.round
    end

    # One option per whole account and per held security, as [label, "account_id|security_id"]
    def allocation_options
      accounts = Current.family.accounts.visible.alphabetically.includes(:accountable)

      accounts.flat_map do |account|
        whole = [ [ account.name, account.id ] ]

        if account.accountable_type == "Investment"
          holdings = account.current_holdings.includes(:security).map do |holding|
            [ "#{account.name} - #{holding.security.display_name}", "#{account.id}|#{holding.security_id}" ]
          end
          whole + holdings
        else
          whole
        end
      end
    end
end
