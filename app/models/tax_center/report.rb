# Realized capital gains for one financial year across a set of accounts (one person's accounts, since
# the LTCG exemption is per individual), with the netted per-redemption view and an indicative tax estimate.
class TaxCenter::Report
  RedemptionRow = Struct.new(:redemption, :lines, :tds, keyword_init: true) do
    def short_term_gain
      lines.select { |l| l.term == :short }.sum(&:gain)
    end

    def long_term_gain
      lines.select { |l| l.term == :long }.sum(&:gain)
    end

    def gain
      redemption.gain
    end
  end

  attr_reader :family, :accounts, :slab_rate, :rules, :residency

  # residency: a TaxCenter::Residency. For an NRI the report adds the estimated TDS deducted on each sale.
  def initialize(family:, accounts:, financial_year_start: Period.financial_year_start(Date.current), slab_rate: 30, tax_lots: nil,
                 rules: TaxCenter::Rules.current, residency: nil)
    @family = family
    @residency = residency || TaxCenter::Residency.new(rules: rules)
    @accounts = accounts.to_a
    @financial_year_start = financial_year_start
    @slab_rate = BigDecimal(slab_rate.to_s)
    @tax_lots = tax_lots
    @rules = rules
  end

  def period
    @period ||= Period.financial_year_for(@financial_year_start)
  end

  def label
    Period.financial_year_label(@financial_year_start)
  end

  def tax_lots
    @tax_lots ||= Holding::TaxLots.new(accounts, currency: family.currency)
  end

  def lines
    @lines ||= tax_lots.realized_between(period.start_date, period.end_date).map { |lot| line_for(lot) }
  end

  def redemption_rows
    @redemption_rows ||= tax_lots.redemptions_between(period.start_date, period.end_date).map do |redemption|
      lines = redemption.lots.map { |lot| line_for(lot) }
      RedemptionRow.new(redemption: redemption, lines: lines, tds: residency.tds_for_lines(lines, redemption.date))
    end.sort_by { |row| [ row.redemption.date, row.redemption.security.display_name ] }
  end

  # Estimated TDS an AMC or broker deducts on this year's sales (NRI only; zero otherwise)
  def tds_total
    redemption_rows.sum(BigDecimal("0")) { |row| row.tds }
  end

  def exemption_limit
    rules.ltcg_equity_exemption(period.start_date)
  end

  def estimate
    @estimate ||= TaxCenter::Estimate.new(
      gains: lines.map { |line| [ line.classification, line.gain ] },
      slab_rate: slab_rate,
      exemption_limit: exemption_limit
    )
  end

  def warnings
    lines.flat_map { |line| line.notes }.uniq
  end

  def grandfathering_lines
    lines.select { |line| line.classification.grandfathering_warning }
  end

  private
    def line_for(lot)
      @category_cache ||= {}
      TaxCenter::GainLine.for(lot, family: family, rules: rules, category_cache: @category_cache)
    end
end
