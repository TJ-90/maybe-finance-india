# An Indian mutual fund scheme as published by AMFI (NAVAll.txt). This table powers fund discovery and
# the MF search in the trade form. The scheme code doubles as the ticker of the matching Security
# (with the pseudo-MIC Security::AMFI_MIC).
class MutualFundScheme < ApplicationRecord
  # Below this many rows a file is assumed to be partial, so schemes missing from it are not deactivated.
  MIN_ROWS_TO_DEACTIVATE_MISSING = 500

  enum :plan, { direct: "direct", regular: "regular" }, validate: { allow_nil: true }
  enum :option, { growth: "growth", idcw: "idcw" }, validate: { allow_nil: true }
  enum :asset_class, Security::ASSET_CLASSES.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :tax_category, Security::TAX_CATEGORIES.index_with(&:itself), prefix: true, validate: { allow_nil: true }

  validates :scheme_code, :name, presence: true
  validates :scheme_code, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :alphabetically, -> { order(:name) }
  # Index funds and ETFs, recognised by name (AMFI has no explicit active/passive flag)
  PASSIVE_PATTERN = '\m(index|etf|exchange traded)\M'.freeze
  scope :passive, -> { where("mutual_fund_schemes.name ~* :p OR mutual_fund_schemes.category ~* :p", p: PASSIVE_PATTERN) }
  scope :actively_managed, -> { where.not(id: passive.select(:id)) }

  EQUITY_ORIENTED_HYBRIDS = /arbitrage|equity savings|aggressive hybrid/i
  DEBT_WORDS = /\b(liquid|gilt|g-?sec|sdl|bond|debt|t-?bill|treasury|money market|overnight|fixed maturity|income)\b/i

  class << self
    # Every word must appear in the name, AMC or scheme code (or match an ISIN exactly)
    def search(query)
      terms = query.to_s.split(/\s+/).reject(&:blank?)
      return all if terms.empty?

      terms.reduce(all) do |scope, term|
        pattern = "%#{sanitize_sql_like(term)}%"
        scope.where(
          "mutual_fund_schemes.name ILIKE :p OR mutual_fund_schemes.amc ILIKE :p OR mutual_fund_schemes.scheme_code = :t OR mutual_fund_schemes.isin_growth = :t OR mutual_fund_schemes.isin_reinvestment = :t",
          p: pattern, t: term.upcase
        )
      end
    end

    # Fund discovery. `style` is "passive" (index funds and ETFs) or "active".
    def discover(q: nil, amc: nil, category: nil, plan: nil, option: nil, style: nil)
      scope = active.search(q)
      scope = scope.where(amc: amc) if amc.present?
      scope = scope.where(category: category) if category.present?
      scope = scope.where(plan: plan) if plans.key?(plan.to_s)
      scope = scope.where(option: option) if options.key?(option.to_s)
      scope = scope.passive if style.to_s == "passive"
      scope = scope.actively_managed if style.to_s == "active"
      scope
    end

    def amcs
      active.where.not(amc: [ nil, "" ]).distinct.order(:amc).pluck(:amc)
    end

    def categories
      active.where.not(category: [ nil, "" ]).distinct.order(:category).pluck(:category)
    end

    # Upserts parsed NAVAll rows (see Provider::Amfi::SchemeRow). Returns the number of schemes written.
    def import_rows!(rows, deactivate_missing: rows.size >= MIN_ROWS_TO_DEACTIVATE_MISSING)
      records = rows.map do |row|
        {
          scheme_code: row.scheme_code,
          name: row.name,
          amc: row.amc,
          category: row.category,
          scheme_type: row.scheme_type,
          plan: row.plan,
          option: row.option,
          isin_growth: row.isin_growth,
          isin_reinvestment: row.isin_reinvestment,
          latest_nav: row.nav,
          nav_date: row.nav_date,
          asset_class: row.asset_class,
          tax_category: row.tax_category,
          active: true
        }
      end.uniq { |r| r[:scheme_code] }

      return 0 if records.empty?

      transaction do
        records.each_slice(1000) { |batch| upsert_all(batch, unique_by: :scheme_code) }
        where.not(scheme_code: records.map { |r| r[:scheme_code] }).update_all(active: false) if deactivate_missing
      end

      records.size
    end

    # Imports an AMFI NAVAll.txt that was downloaded by hand (offline fallback for the nightly job).
    # Returns the number of schemes imported; raises ArgumentError when the file is not a NAVAll.txt.
    def import_navall!(io)
      rows = Provider::Amfi.parse_navall(io)
      raise ArgumentError, "No mutual fund schemes found. Upload the NAVAll.txt file from amfiindia.com." if rows.empty?

      count = import_rows!(rows)
      record_latest_prices!
      count
    end

    # Writes the latest published NAV as a Security::Price for every mutual fund security we already track.
    # Returns the number of prices written.
    def record_latest_prices!
      written = 0

      Security.where(exchange_operating_mic: Security::AMFI_MIC).find_each do |security|
        scheme = find_by(scheme_code: security.ticker)
        next unless scheme&.latest_nav && scheme.nav_date

        Security::Price.upsert(
          { security_id: security.id, date: scheme.nav_date, price: scheme.latest_nav, currency: "INR" },
          unique_by: %i[security_id date currency]
        )
        written += 1
      end

      written
    end

    def last_nav_date
      maximum(:nav_date)
    end

    # ---- Classification from AMFI names and categories ----

    def infer_plan(name)
      name.to_s.match?(/\bdirect\b/i) ? "direct" : "regular"
    end

    # Looks at the part after the first " - " (the plan/option suffix) so a fund called
    # "Dividend Yield Fund - Growth" is not mistaken for an IDCW option.
    def infer_option(name)
      suffix = name.to_s.split(/\s+-\s+/, 2)[1] || name.to_s
      return "idcw" if suffix.match?(/idcw|dividend|payout|reinvest|bonus/i)
      return "growth" if suffix.match?(/growth/i)

      "growth"
    end

    def infer_asset_class(category, name)
      category = category.to_s
      name = name.to_s

      return "gold" if name.match?(/\b(gold|silver)\b/i) || category.match?(/\b(gold|silver)\b/i)
      return "international" if category.match?(/international|overseas/i) || name.match?(/international|overseas|nasdaq|s&p 500/i)

      case category
      when /\AEquity/i, /elss/i then "equity"
      when /\ADebt/i then "debt"
      when /\AHybrid/i, /\ASolution Oriented/i, /balanced/i then "hybrid"
      when /index|etf/i
        name.match?(DEBT_WORDS) ? "debt" : "equity"
      when /fof/i
        name.match?(DEBT_WORDS) ? "debt" : "other"
      when /\A(growth)\z/i then "equity"
      when DEBT_WORDS then "debt"
      else "other"
      end
    end

    # Rough mapping to the Indian MF tax buckets. Always overridable per family.
    #  - equity: equity-oriented funds (>= 65% domestic equity), incl. arbitrage, equity savings, aggressive hybrid
    #  - debt: debt and liquid funds
    #  - other_listed: listed units (ETFs) that are not equity or debt
    #  - other_unlisted: everything else (international FoFs, gold FoFs, multi-asset, balanced advantage, ...)
    def infer_tax_category(category, name, asset_class: nil)
      asset_class ||= infer_asset_class(category, name)
      listed = category.to_s.match?(/\betf\b/i) || name.to_s.match?(/\betf\b/i)

      if asset_class == "equity" || (asset_class == "hybrid" && category.to_s.match?(EQUITY_ORIENTED_HYBRIDS))
        "equity"
      elsif asset_class == "debt"
        "debt"
      elsif listed
        "other_listed"
      else
        "other_unlisted"
      end
    end
  end

  def to_combobox_option
    Security::SynthComboboxOption.new(
      symbol: scheme_code,
      name: name,
      exchange_operating_mic: Security::AMFI_MIC,
      country_code: "IN",
      kind: "mutual_fund"
    )
  end

  # The Security tracking this scheme, if the user already holds or searched for it
  def security
    Security.find_by(ticker: scheme_code, exchange_operating_mic: Security::AMFI_MIC)
  end

  # NAV history as [date, nav] pairs, oldest first. Once the scheme is tracked as a Security, history is
  # cached into security_prices; until then it is fetched live so browsing funds does not create securities.
  def nav_history(since: 1.year.ago.to_date)
    provider = Security.provider
    return [] if provider.nil?

    if (tracked = security)
      tracked.import_provider_prices(start_date: since, end_date: Date.current)
      return tracked.prices.where(date: since..).order(:date).pluck(:date, :price)
    end

    response = provider.fetch_security_prices(
      symbol: scheme_code,
      exchange_operating_mic: Security::AMFI_MIC,
      start_date: since,
      end_date: Date.current
    )

    response.success? ? response.data.sort_by(&:date).map { |p| [ p.date, p.price ] } : []
  end

  # Finds or creates the Security for this scheme so trades can reference it
  def find_or_create_security!
    Security.find_or_create_by!(ticker: scheme_code, exchange_operating_mic: Security::AMFI_MIC) do |security|
      security.name = name
      security.country_code = "IN"
    end
  end

  def latest_nav_money
    latest_nav && Money.new(latest_nav, "INR")
  end
end
