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

  # Total percentage already allocated to the same account (and security) by other goals
  def allocated_elsewhere
    GoalAllocation
      .where(account_id: account_id, security_id: security_id)
      .where.not(id: id)
      .sum(:percentage)
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

      errors.add(:percentage, "would allocate #{total.to_f.round(2)}% of this holding across all goals (maximum 100%)")
    end
end
