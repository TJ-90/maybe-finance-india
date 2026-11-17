# Which household member an account belongs to (the owner or first holder). No member means
# "Joint / household". Also holds the warnings that depend on the owner's residency: they are shown,
# never enforced, because the rules differ by instrument and change over time.
module Account::Ownership
  extend ActiveSupport::Concern

  JOINT_LABEL = "Joint / household".freeze

  included do
    belongs_to :household_member, optional: true

    validate :household_member_belongs_to_family

    scope :owned_by, ->(member) { where(household_member_id: member&.id) }
  end

  def owner_name
    household_member&.name || JOINT_LABEL
  end

  # Plain-language warnings for the owner's residency, e.g. a PPF held by an NRI
  def residency_warnings
    return [] unless household_member&.nri?

    warnings = []

    case [ accountable_type, subtype ]
    when [ "ProvidentFund", "ppf" ]
      warnings << "An NRI cannot open a new PPF. An existing PPF can continue until maturity but cannot be extended."
    when [ "ProvidentFund", "ssy" ]
      warnings << "Sukanya Samriddhi accounts are for resident girl children. If the account holder becomes an NRI the account must be closed, so check the rules with the post office or bank."
    when [ "Depository", "savings" ], [ "Depository", "checking" ]
      warnings << "NRIs must hold bank accounts as NRE or NRO. Consider switching this account's type to NRE or NRO."
    end

    warnings
  end

  private
    def household_member_belongs_to_family
      return if household_member.blank? || household_member.family_id == family_id

      errors.add(:household_member, "must belong to the same household")
    end
end
