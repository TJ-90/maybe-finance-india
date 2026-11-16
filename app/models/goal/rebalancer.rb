# Compares what a goal actually holds (equity / debt / gold / other) with the equity share the
# glide path asks for today, and suggests a move when the gap is more than DRIFT_THRESHOLD points.
#
# Classification:
#   * Holdings use Security#effective_asset_class(family). Hybrid funds are split 50/50 between
#     equity and debt, international funds count as equity, anything unknown is "other".
#   * Whole accounts are classified by type: Depository, FixedDeposit and ProvidentFund are debt,
#     PreciousMetal is gold, other types are "other". For an investment account, holdings are
#     classified individually and the remaining cash is debt.
#   * The glide path only knows equity vs. not-equity, so gold and "other" sit on the non-equity side.
class Goal::Rebalancer
  DRIFT_THRESHOLD = 5.0
  BUCKETS = %i[equity debt gold other].freeze
  DEBT_ACCOUNT_TYPES = %w[Depository FixedDeposit ProvidentFund].freeze

  Suggestion = Data.define(:from, :to, :amount, :drift)

  attr_reader :goal, :today

  def initialize(goal, today: Date.current)
    @goal = goal
    @today = today
  end

  def amounts
    @amounts ||= classify
  end

  def total
    amounts.values.sum
  end

  def current_split
    return BUCKETS.index_with { 0.0 } if total.zero?

    BUCKETS.index_with { |bucket| amounts[bucket] / total * 100 }
  end

  def target_equity_pct
    goal.glide_path.equity_pct_for(today)
  end

  # Positive when equity is above the glide-path target
  def drift
    current_split[:equity] - target_equity_pct
  end

  def rebalance_needed?
    total.positive? && drift.abs > DRIFT_THRESHOLD
  end

  def suggestions
    return [] unless rebalance_needed?

    amount = Money.new(drift.abs / 100 * total, goal.currency)

    if drift.positive?
      [ Suggestion.new(from: "equity", to: "debt", amount: amount, drift: drift) ]
    else
      [ Suggestion.new(from: "debt", to: "equity", amount: amount, drift: drift) ]
    end
  end

  private
    def classify
      buckets = BUCKETS.index_with { 0.0 }

      goal.goal_allocations.includes(:security, account: :accountable).each do |allocation|
        if allocation.security
          add_security(buckets, allocation.security, allocation.value.amount.to_f)
        else
          add_account(buckets, allocation)
        end
      end

      buckets
    end

    def add_account(buckets, allocation)
      account = allocation.account
      fraction = allocation.percentage.to_f / 100

      case account.accountable_type
      when *DEBT_ACCOUNT_TYPES
        buckets[:debt] += allocation.value.amount.to_f
      when "PreciousMetal"
        buckets[:gold] += allocation.value.amount.to_f
      when "Investment"
        holdings_total = 0.0

        account.current_holdings.includes(:security).each do |holding|
          amount = convert(holding.amount_money) * fraction
          holdings_total += convert(holding.amount_money)
          add_security(buckets, holding.security, amount)
        end

        # Whatever is not in a holding is cash
        cash = convert(account.balance_money) - holdings_total
        buckets[:debt] += cash * fraction if cash.positive?
      else
        buckets[:other] += allocation.value.amount.to_f
      end
    end

    def add_security(buckets, security, amount)
      case security.effective_asset_class(goal.family)
      when "equity", "international"
        buckets[:equity] += amount
      when "debt"
        buckets[:debt] += amount
      when "gold"
        buckets[:gold] += amount
      when "hybrid"
        buckets[:equity] += amount / 2
        buckets[:debt] += amount / 2
      else
        buckets[:other] += amount
      end
    end

    def convert(money)
      money.exchange_to(goal.currency, fallback_rate: 1).amount.to_f
    end
end
