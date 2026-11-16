# Links part of an account (or of one security held in an account) to a goal. The same holding can
# fund several goals as long as the percentages across all goals add up to 100 or less.
class GoalAllocation < ApplicationRecord
  belongs_to :goal
  belongs_to :account
  belongs_to :security, optional: true

  validates :percentage, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :account_id, uniqueness: { scope: %i[goal_id security_id], message: "is already allocated to this goal" }
  validate :account_belongs_to_goal_family
  validate :total_across_goals_within_limit

  # Value of this allocation in the goal currency. With a security, only that holding counts;
  # otherwise the whole account balance does.
  def value
    converted = base_money.exchange_to(goal.currency, fallback_rate: 1)
    Money.new(converted.amount * percentage / 100, goal.currency)
  end

  # Percentage of this holding that is already spoken for by other allocations. A whole-account
  # allocation covers every holding in the account, so the two kinds overlap:
  #   * for a security allocation: other allocations of the same security + all whole-account ones
  #   * for a whole-account allocation: other whole-account ones + the most-allocated single security
  def allocated_elsewhere
    others = GoalAllocation.where(account_id: account_id).where.not(id: id)
    account_level = others.where(security_id: nil).sum(:percentage)

    if security_id
      account_level + others.where(security_id: security_id).sum(:percentage)
    else
      account_level + (others.where.not(security_id: nil).group(:security_id).sum(:percentage).values.max || 0)
    end
  end

  def holding
    return nil unless security_id

    account.current_holdings.find_by(security_id: security_id)
  end

  def target_label
    security ? "#{account.name} - #{security.display_name}" : account.name
  end

  private
    def base_money
      if security_id
        holding&.amount_money || Money.new(0, account.currency)
      else
        account.balance_money
      end
    end

    def account_belongs_to_goal_family
      return unless account && goal

      errors.add(:account, "must belong to your family") unless account.family_id == goal.family_id
    end

    def total_across_goals_within_limit
      return if percentage.blank? || account_id.blank?

      total = allocated_elsewhere + percentage
      return if total <= 100

      errors.add(:percentage, "would allocate #{total.to_f.round(2)}% of this holding across all goals, counting whole-account and per-holding allocations together (maximum 100%)")
    end
end
