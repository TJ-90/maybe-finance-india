# A financial goal (retirement, education, home...) with a target in today's money. Goals are plain
# planning records: they never touch account balances. Accounts and holdings are linked through
# GoalAllocation, and everything is derived on read.
class Goal < ApplicationRecord
  include Monetizable

  KINDS = {
    "retirement" => "Retirement",
    "education" => "Education",
    "home" => "Home",
    "vehicle" => "Vehicle",
    "wedding" => "Wedding",
    "travel" => "Travel",
    "emergency_fund" => "Emergency fund",
    "custom" => "Custom"
  }.freeze

  DEFAULT_EMERGENCY_MONTHS = 6
  EXPENSE_LOOKBACK_MONTHS = 6

  belongs_to :family
  has_many :goal_allocations, dependent: :destroy

  monetize :target_amount, :monthly_sip, :monthly_expenses_today

  before_validation :default_retirement_target_date, :default_blank_amounts

  validates :name, :currency, presence: true
  validates :kind, inclusion: { in: KINDS.keys }
  validates :target_date, presence: true
  validates :target_amount, numericality: { greater_than: 0 }, unless: :retirement?
  validates :monthly_sip, numericality: { greater_than_or_equal_to: 0 }
  validates :inflation_rate, :expected_equity_return, :expected_debt_return,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 50 }
  validates :sip_step_up_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :initial_equity_pct, :final_equity_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :glide_path_years, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 50 }
  validate :retirement_fields_valid, if: :retirement?

  scope :ordered, -> { order(:target_date, :name) }

  def kind_label
    KINDS.fetch(kind, kind.to_s.humanize)
  end

  def retirement?
    kind == "retirement"
  end

  def emergency_fund?
    kind == "emergency_fund"
  end

  def glide_path
    Goal::GlidePath.new(
      initial_equity_pct: initial_equity_pct,
      final_equity_pct: final_equity_pct,
      glide_path_years: glide_path_years,
      target_date: target_date
    )
  end

  def projection(today: Date.current)
    Goal::Projection.new(self, today: today)
  end

  def rebalancer(today: Date.current)
    Goal::Rebalancer.new(self, today: today)
  end

  # Total of all allocations in the goal currency
  def allocated_value
    goal_allocations.includes(:account, :security).to_a.sum(Money.new(0, currency), &:value)
  end

  # Average monthly expenses over the last six full months, in the goal currency. Zero when there
  # is no expense history.
  def average_monthly_expenses
    end_date = Date.current.beginning_of_month - 1.day
    start_date = (end_date - (EXPENSE_LOOKBACK_MONTHS - 1).months).beginning_of_month
    period = Period.custom(start_date: start_date, end_date: end_date)

    total = IncomeStatement.new(family).expense_totals(period: period).total
    total_money = Money.new(total, family.currency).exchange_to(currency, fallback_rate: 1)

    Money.new(total_money.amount / EXPENSE_LOOKBACK_MONTHS, currency)
  end

  def emergency_fund_target(months: DEFAULT_EMERGENCY_MONTHS)
    Money.new(average_monthly_expenses.amount * months, currency)
  end

  private
    # Retirement targets are derived from expenses, and a blank SIP means none yet
    def default_blank_amounts
      self.target_amount = 0 if target_amount.blank? && retirement?
      self.monthly_sip = 0 if monthly_sip.blank?
    end

    # A retirement goal's date is implied by the ages, so people don't have to enter both.
    def default_retirement_target_date
      return unless retirement? && target_date.blank? && current_age && retirement_age

      self.target_date = Date.current + (retirement_age - current_age).years
    end

    def retirement_fields_valid
      %i[current_age retirement_age life_expectancy].each do |field|
        errors.add(field, "can't be blank") if self[field].blank?
      end
      errors.add(:monthly_expenses_today, "can't be blank") if monthly_expenses_today.blank?
      errors.add(:post_retirement_return, "can't be blank") if post_retirement_return.blank?
      return if errors.any?

      errors.add(:retirement_age, "must be greater than current age") unless retirement_age > current_age
      errors.add(:life_expectancy, "must be greater than retirement age") unless life_expectancy > retirement_age
    end
end
