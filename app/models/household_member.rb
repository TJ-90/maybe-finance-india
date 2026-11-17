# One person in the household. Tax depends on the person (the LTCG exemption is per individual, and an
# NRI is taxed and has TDS deducted differently), so accounts can belong to a member and the Tax Center
# works one member at a time. Accounts with no member are "Joint / household".
#
# Residency has no default on purpose: every member is asked "Resident or NRI?" explicitly.
class HouseholdMember < ApplicationRecord
  RELATIONSHIPS = {
    "self" => "Myself",
    "spouse" => "Spouse",
    "parent" => "Parent",
    "child" => "Child",
    "other" => "Other"
  }.freeze

  RESIDENCY_STATUSES = {
    "resident" => "Resident",
    "nri" => "NRI"
  }.freeze

  TAX_REGIMES = {
    "new" => "New regime",
    "old" => "Old regime"
  }.freeze

  COLORS = %w[#1570EF #0E9384 #7C3AED #F79009 #D92D20 #06AED4].freeze

  belongs_to :family
  has_many :accounts, dependent: :nullify
  has_many :users, dependent: :nullify
  has_many :goals, dependent: :nullify

  before_validation :default_slab_rate_for_nri, :default_color

  validates :name, presence: true
  validates :relationship, inclusion: { in: RELATIONSHIPS.keys }
  validates :residency_status, inclusion: { in: RESIDENCY_STATUSES.keys, message: "must be chosen: Resident or NRI" }
  validates :tax_regime, inclusion: { in: TAX_REGIMES.keys }
  validates :pan_last4, format: { with: /\A[A-Z0-9]{4}\z/, message: "must be exactly 4 letters or digits" }, allow_blank: true
  validates :slab_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :relationship, uniqueness: { scope: :family_id, message: "can only be chosen once: only one member can be you" }, if: :myself?
  validate :date_of_birth_not_in_future

  normalizes :name, with: ->(value) { value.to_s.squish }
  normalizes :pan_last4, with: ->(value) { value.to_s.strip.upcase.presence }

  scope :ordered, -> { order(Arel.sql("CASE relationship WHEN 'self' THEN 0 WHEN 'spouse' THEN 1 ELSE 2 END"), :name) }

  def myself?
    relationship == "self"
  end

  def nri?
    residency_status == "nri"
  end

  def resident?
    residency_status == "resident"
  end

  def residency_label
    RESIDENCY_STATUSES[residency_status]
  end

  def relationship_label
    RELATIONSHIPS[relationship]
  end

  def first_name
    name.to_s.split.first.to_s
  end

  # Age in whole years on `date`, or nil without a date of birth
  def age(on: Date.current)
    return nil if date_of_birth.blank?

    years = on.year - date_of_birth.year
    years -= 1 if on < birthday_in(on.year)
    years
  end

  # Slab rate to start from in the Tax Center: the member's own, else the data-driven default
  def tax_slab_rate
    slab_rate || TaxCenter::Rules.current.default_slab_rate(residency_status)
  end

  def display_label
    "#{name} (#{residency_label})"
  end

  private
    # An NRI's slab rate defaults to 30%; a resident is asked for theirs
    def default_slab_rate_for_nri
      return unless nri? && slab_rate.blank?

      self.slab_rate = TaxCenter::Rules.current.default_slab_rate("nri")
    end

    def default_color
      self.color = COLORS[(family&.household_members&.count).to_i % COLORS.size] if color.blank?
    end

    # 29 February birthdays fall on 1 March in other years
    def birthday_in(year)
      Date.new(year, date_of_birth.month, date_of_birth.day)
    rescue Date::Error
      Date.new(year, 3, 1)
    end

    def date_of_birth_not_in_future
      errors.add(:date_of_birth, "can't be in the future") if date_of_birth.present? && date_of_birth > Date.current
    end
end
