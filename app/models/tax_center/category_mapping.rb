# Lists the securities a family has traded with their effective tax category and asset class, and lets the
# family override them (stored in family_security_overrides, so other families are unaffected).
class TaxCenter::CategoryMapping
  Row = Struct.new(:security, :tax_category, :asset_class, :override, keyword_init: true) do
    def overridden?
      override.present?
    end

    def unclassified?
      tax_category.blank?
    end
  end

  attr_reader :family

  def initialize(family)
    @family = family
  end

  def securities
    Security.where(id: Trade.joins(:entry).where(entries: { account_id: family.accounts_with_investments.select(:id) }).select(:security_id))
            .order(:name, :ticker)
  end

  def rows
    overrides = family.family_security_overrides.index_by(&:security_id)

    securities.map do |security|
      override = overrides[security.id]
      Row.new(
        security: security,
        tax_category: override&.tax_category.presence || security.tax_category,
        asset_class: override&.asset_class.presence || security.asset_class,
        override: override
      )
    end
  end

  # Blank values clear that part of the override. An override with nothing left is removed.
  # Returns the override (persisted or destroyed), or one with errors when a value is invalid.
  def update(security_id:, tax_category:, asset_class:)
    security = securities.find(security_id)
    override = family.family_security_overrides.find_or_initialize_by(security: security)
    override.tax_category = tax_category.presence
    override.asset_class = asset_class.presence

    if override.tax_category.nil? && override.asset_class.nil?
      override.destroy if override.persisted?
    else
      override.save
    end

    override
  end
end
