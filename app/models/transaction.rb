class Transaction < ApplicationRecord
  include Entryable, Transferable, Ruleable

  PAYMENT_MODES = %w[upi neft imps rtgs card atm nach cheque cash other].freeze

  belongs_to :category, optional: true
  belongs_to :merchant, optional: true

  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings

  accepts_nested_attributes_for :taggings, allow_destroy: true

  enum :kind, {
    standard: "standard", # A regular transaction, included in budget analytics
    funds_movement: "funds_movement", # Movement of funds between accounts, excluded from budget analytics
    cc_payment: "cc_payment", # A CC payment, excluded from budget analytics (CC payments offset the sum of expense transactions)
    loan_payment: "loan_payment", # A payment to a Loan account, treated as an expense in budgets
    one_time: "one_time" # A one-time expense/income, excluded from budget analytics
  }

  validates :payment_mode, inclusion: { in: PAYMENT_MODES }, allow_nil: true

  # Short label for the payment-mode badge (UPI, NEFT, ... Other)
  def payment_mode_label
    return if payment_mode.blank?

    payment_mode == "other" ? "Other" : payment_mode.upcase
  end

  # Overarching grouping method for all transfer-type transactions
  def transfer?
    funds_movement? || cc_payment? || loan_payment?
  end

  def set_category!(category)
    if category.is_a?(String)
      category = entry.account.family.categories.find_or_create_by!(
        name: category
      )
    end

    update!(category: category)
  end
end
