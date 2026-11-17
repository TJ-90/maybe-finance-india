# Reads config/india_capital_gains.yml and classifies a sale of one lot.
class TaxCenter::Rules
  CONFIG_PATH = Rails.root.join("config/india_capital_gains.yml")
  DEFAULT_CATEGORY = "other_unlisted".freeze

  # bucket is one of :stcg_equity, :ltcg_equity, :slab, :ltcg_other, :exempt
  # rate is a percentage (BigDecimal), or nil when the slab rate applies
  Classification = Struct.new(:category, :term, :bucket, :rate, :exemption_eligible, :notes, :grandfathering_warning, keyword_init: true) do
    def long_term?
      term == :long
    end

    def slab?
      bucket == :slab
    end

    def exempt?
      bucket == :exempt
    end
  end

  class << self
    def current
      @current ||= new(load_config)
    end

    def reload!
      @current = nil
    end

    private
      def load_config
        YAML.safe_load_file(CONFIG_PATH, permitted_classes: [ Date ], aliases: false)
      end
  end

  def initialize(config)
    @config = config.deep_symbolize_keys
  end

  def grandfathering_cutoff
    @config.dig(:grandfathering, :cutoff)
  end

  # Section 112A exemption for the financial year containing the given date
  def ltcg_equity_exemption(date)
    entry = effective_entry(@config.fetch(:ltcg_equity_exemption), date, key: :effective_from)
    BigDecimal((entry ? entry[:amount] : 0).to_s)
  end

  # --- Residential status (the `residency:` section of the config) ---------------------------------

  # Default slab rate (BigDecimal %) for a residency status, or nil when the person should be asked
  def default_slab_rate(status)
    value = @config.dig(:residency, :default_slab_rate, status.to_s.to_sym)
    value && BigDecimal(value.to_s)
  end

  def residency_notes(status)
    Array(@config.dig(:residency, status.to_s.to_sym, :notes))
  end

  # TDS rates (% before cess) an AMC or broker deducts from an NRI's sale proceeds, by sale date.
  # Keys: :equity_stcg, :equity_ltcg, :debt_mf, :other_stcg, :other_ltcg
  def nri_tds_rates(date)
    entry = effective_entry(@config.dig(:residency, :nri, :tds, :rates), date, key: :effective_from)
    entry.except(:effective_from).transform_values { |rate| BigDecimal(rate.to_s) }
  end

  def nri_tds_cess_percent
    BigDecimal(@config.dig(:residency, :nri, :tds, :cess_percent).to_s)
  end

  def nri_tds_surcharge_note
    @config.dig(:residency, :nri, :tds, :surcharge_note)
  end

  def nri_tds_dtaa_note
    @config.dig(:residency, :nri, :tds, :dtaa_note)
  end

  # Whether the Sec 112A exemption lowers the TDS an NRI sees (it normally does not: it is a refund claim)
  def nri_tds_considers_ltcg_exemption?
    @config.dig(:residency, :nri, :tds, :ltcg_equity_exemption_reduces_tds) == true
  end

  # Interest-income rules: { resident_tds_rate:, nri_nro_tds_rate:, epf_contribution_limit: { ... } }
  def interest_rules
    @config.dig(:residency, :interest)
  end

  # { general:, senior_citizen: } bank TDS thresholds for residents, for the year containing `date`
  def resident_interest_tds_threshold(date)
    entry = effective_entry(interest_rules.fetch(:resident_tds_threshold), date, key: :effective_from)
    entry.slice(:general, :senior_citizen).transform_values { |amount| BigDecimal(amount.to_s) }
  end

  # The category actually used for tax, after resolving unknown categories and debt purchase-date rules
  def resolve_category(category, buy_date:)
    category = category.presence || DEFAULT_CATEGORY
    return category unless category == "debt"

    rule = @config.dig(:categories, :debt, :purchase_rules).find { |r| buy_date >= r[:purchased_on_or_after] }
    rule[:always_slab] ? "debt" : rule.fetch(:use_category)
  end

  def classify(category:, buy_date:, sell_date:)
    unclassified = category.blank?
    resolved = resolve_category(category, buy_date: buy_date)
    notes = []
    notes << "No tax category set for this security; treated as #{DEFAULT_CATEGORY.humanize.downcase}. Fix it under Category mapping." if unclassified

    if resolved == "debt"
      note = @config.dig(:categories, :debt, :purchase_rules).find { |r| r[:always_slab] }[:note]
      return Classification.new(category: resolved, term: :short, bucket: :slab, rate: nil,
                                exemption_eligible: false, notes: notes + [ note ])
    end

    definition = @config.dig(:categories, resolved.to_sym)
    raise ArgumentError, "Unknown tax category #{resolved}" if definition.nil?

    if definition[:exempt]
      return Classification.new(category: resolved, term: :long, bucket: :exempt, rate: BigDecimal("0"),
                                exemption_eligible: false, notes: notes)
    end

    rule = effective_entry(definition.fetch(:rules), sell_date, key: :effective_from)
    long_term = buy_date.advance(months: rule.fetch(:long_term_after_months)) < sell_date
    notes << rule[:note] if long_term && rule[:note].present? && rule[:indexation]

    rate = long_term ? rule.fetch(:ltcg_rate) : rule.fetch(:stcg_rate)
    bucket =
      if rate == "slab" then :slab
      elsif resolved == "equity" then long_term ? :ltcg_equity : :stcg_equity
      else :ltcg_other
      end

    warning = resolved == "equity" && grandfathering_cutoff && buy_date <= grandfathering_cutoff
    if warning
      notes << "Bought on or before #{grandfathering_cutoff}: grandfathered cost (FMV on that date) is not applied. Actual cost is used, so the gain may be overstated."
    end

    Classification.new(
      category: resolved,
      term: long_term ? :long : :short,
      bucket: bucket,
      rate: rate == "slab" ? nil : BigDecimal(rate.to_s),
      exemption_eligible: bucket == :ltcg_equity && rule[:exemption_eligible] == true,
      notes: notes,
      grandfathering_warning: warning ? true : false
    )
  end

  private
    # The entry with the latest effective date that is on or before `date`
    def effective_entry(entries, date, key:)
      entries.select { |entry| entry[key] <= date }.max_by { |entry| entry[key] }
    end
end
