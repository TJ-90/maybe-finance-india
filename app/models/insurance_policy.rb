# An insurance policy held by a family. This is NOT an account: it has no balance, is never part of
# net worth, and only exists so premiums and cover are in one place.
class InsurancePolicy < ApplicationRecord
  include Monetizable

  KINDS = {
    "term" => "Term life",
    "life" => "Life (endowment / whole life)",
    "health" => "Health",
    "ulip" => "ULIP",
    "vehicle" => "Vehicle",
    "home" => "Home",
    "other" => "Other"
  }.freeze

  # Months between premiums. "single" is a one-time premium with no next due date.
  PREMIUM_FREQUENCIES = {
    "monthly" => 1,
    "quarterly" => 3,
    "half_yearly" => 6,
    "yearly" => 12,
    "single" => nil
  }.freeze

  MAX_DOCUMENT_SIZE = 10.megabytes
  DOCUMENT_TYPES = %w[application/pdf image/jpeg image/png].freeze

  belongs_to :family

  has_many_attached :documents

  # Policy numbers identify the policyholder to the insurer, so they are encrypted at rest
  encrypts :policy_number

  monetize :sum_assured, :premium

  validates :kind, inclusion: { in: KINDS.keys }
  validates :premium_frequency, inclusion: { in: PREMIUM_FREQUENCIES.keys }, allow_blank: true
  validates :insurer, :currency, presence: true
  validates :sum_assured, :premium, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :end_date_after_start_date
  validate :documents_are_acceptable

  scope :ordered, -> { order(Arel.sql("next_premium_due_on ASC NULLS LAST"), :insurer) }

  # Policies whose next premium falls within the window, soonest first
  scope :premium_due_within, ->(window = 30.days) {
    where(next_premium_due_on: Date.current..(Date.current + window)).order(:next_premium_due_on)
  }

  def kind_label
    KINDS.fetch(kind, kind.to_s.humanize)
  end

  def active?(date = Date.current)
    end_date.nil? || end_date >= date
  end

  # "XXXX 1234" style label for lists, never the whole number
  def masked_policy_number
    return nil if policy_number.blank?

    "XXXX #{policy_number.to_s.last(4)}"
  end

  def days_until_premium(date = Date.current)
    (next_premium_due_on - date).to_i if next_premium_due_on
  end

  # After a premium is paid, roll the due date forward by one period (single-premium policies have no next due date)
  def advance_premium_due!
    months = PREMIUM_FREQUENCIES[premium_frequency]

    if months.nil? || next_premium_due_on.nil?
      update!(next_premium_due_on: nil)
    else
      next_due = next_premium_due_on >> months
      next_due = next_due >> months while next_due < Date.current
      update!(next_premium_due_on: end_date && next_due > end_date ? nil : next_due)
    end
  end

  private
    def end_date_after_start_date
      return if start_date.blank? || end_date.blank?

      errors.add(:end_date, "must be after the start date") if end_date < start_date
    end

    def documents_are_acceptable
      documents.each do |document|
        errors.add(:documents, "must be a PDF, JPG or PNG") unless DOCUMENT_TYPES.include?(document.content_type)
        errors.add(:documents, "must be smaller than 10 MB") if document.byte_size > MAX_DOCUMENT_SIZE
      end
    end
end
