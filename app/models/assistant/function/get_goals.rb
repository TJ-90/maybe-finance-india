class Assistant::Function::GetGoals < Assistant::Function
  class << self
    def name
      "get_goals"
    end

    def description
      <<~INSTRUCTIONS
        Use this to see the user's financial goals (retirement, education, home, emergency fund and so on)
        with their target, projected corpus, shortfall and the monthly SIP needed to reach them.

        This is great for answering questions like:
        - Am I on track for my goals?
        - How much SIP do I need for my child's education?
        - Is my portfolio balanced for my goal's glide path?
      INSTRUCTIONS
    end
  end

  def call(params = {})
    {
      as_of_date: Date.current,
      currency: family.currency,
      goals: family.goals.ordered.includes(goal_allocations: [ :account, :security ]).map { |goal| goal_data(goal) }
    }
  end

  private
    def goal_data(goal)
      projection = goal.projection
      rebalancer = goal.rebalancer
      required_sip = projection.required_monthly_sip

      {
        name: goal.name,
        kind: goal.kind,
        target_date: goal.target_date,
        target_in_todays_money: money(projection.target_today, goal.currency),
        inflation_adjusted_target: money(projection.inflation_adjusted_target, goal.currency),
        allocated_value: goal.allocated_value.format,
        monthly_sip: goal.monthly_sip_money.format,
        required_monthly_sip: required_sip && money(required_sip, goal.currency),
        projected_corpus: money(projection.projected_corpus, goal.currency),
        shortfall: money(projection.shortfall, goal.currency),
        surplus: money(projection.surplus, goal.currency),
        progress_percent: projection.progress_pct.round(1),
        on_track: projection.on_track?,
        assumptions: {
          inflation_rate_percent: goal.inflation_rate.to_f,
          expected_equity_return_percent: goal.expected_equity_return.to_f,
          expected_debt_return_percent: goal.expected_debt_return.to_f,
          sip_step_up_percent: goal.sip_step_up_pct.to_f
        },
        target_equity_percent_today: rebalancer.target_equity_pct.round(1),
        rebalancing: rebalancer.suggestions.map do |suggestion|
          "Move #{suggestion.amount.format} from #{suggestion.from} to #{suggestion.to}"
        end
      }
    end

    def money(amount, currency)
      Money.new(amount, currency).format
    end
end
