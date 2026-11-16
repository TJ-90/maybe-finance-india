# Lets a family reclassify a security (e.g. treat a hybrid fund as equity for tax) without changing it for others.
class FamilySecurityOverride < ApplicationRecord
  belongs_to :family
  belongs_to :security

  enum :tax_category, Security::TAX_CATEGORIES.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :asset_class, Security::ASSET_CLASSES.index_with(&:itself), prefix: true, validate: { allow_nil: true }

  validates :security_id, uniqueness: { scope: :family_id }
end
