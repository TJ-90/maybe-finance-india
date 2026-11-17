# Estimates the tax on a planned sale of one folio's holding, consuming open lots first-in-first-out.
#
# `only_held_over_months` is a planning view: it skips lots held for that many months or less, so you can see
# the tax if only older units were sold. An AMC always redeems FIFO, so it will not process a sale that way.
class TaxCenter::SaleSimulator
  attr_reader :lines, :estimate, :baseline, :units_requested, :shortfall, :residency

  def initialize(family:, lots:, units:, sale_date:, price:, slab_rate: 30, realized_stcg: 0, realized_ltcg: 0,
                 only_held_over_months: nil, rules: TaxCenter::Rules.current, residency: nil)
    @family = family
    @rules = rules
    @residency = residency || TaxCenter::Residency.new(rules: rules)
    @sale_date = sale_date
    @price = BigDecimal(price.to_s)
    @units_requested = BigDecimal(units.to_s)
    @only_held_over_months = only_held_over_months.presence&.to_i
    @lots = lots

    @lines = consume
    @shortfall = [ units_requested - lines.sum(&:qty), 0 ].max

    exemption = rules.ltcg_equity_exemption(Period.financial_year_start(sale_date))
    extras = extra_gains(BigDecimal(realized_stcg.to_s), BigDecimal(realized_ltcg.to_s))
    @baseline = TaxCenter::Estimate.new(gains: extras, slab_rate: slab_rate, exemption_limit: exemption)
    @estimate = TaxCenter::Estimate.new(gains: extras + lines.map { |l| [ l.classification, l.gain ] },
                                        slab_rate: slab_rate, exemption_limit: exemption)
  end

  # Extra tax caused by this sale, on top of what was already realized
  def incremental_tax
    estimate.tax - baseline.tax
  end

  # Estimated TDS the AMC or broker deducts from this sale (NRI only; zero otherwise)
  def tds
    residency.tds_for_lines(lines, sale_date)
  end

  def gain
    lines.sum(&:gain)
  end

  def proceeds
    lines.sum(&:proceeds)
  end

  def cost
    lines.sum(&:cost)
  end

  def units
    lines.sum(&:qty)
  end

  def skipped_lots
    @skipped_lots ||= @lots.reject { |lot| eligible?(lot) }
  end

  private
    attr_reader :family, :rules, :sale_date, :price

    def eligible?(lot)
      @only_held_over_months.nil? || lot.buy_date.advance(months: @only_held_over_months) < sale_date
    end

    def consume
      remaining = units_requested
      lines = []

      @lots.select { |lot| eligible?(lot) }.each do |lot|
        break if remaining <= 0

        taken = [ lot.qty, remaining ].min
        remaining -= taken

        realized = Holding::TaxLots::RealizedLot.new(
          account: lot.account, security: lot.security, folio: lot.folio, entry: nil,
          buy_date: lot.buy_date, sell_date: sale_date, qty: taken,
          cost: taken * lot.cost_per_unit, proceeds: taken * price
        )

        category = lot.security.effective_tax_category(family)
        lines << TaxCenter::GainLine.new(
          lot: realized,
          classification: rules.classify(category: category, buy_date: lot.buy_date, sell_date: sale_date)
        )
      end

      lines
    end

    # Equity gains the person has already realized this year, supplied as plain amounts
    def extra_gains(stcg, ltcg)
      short = rules.classify(category: "equity", buy_date: sale_date - 1.day, sell_date: sale_date)
      long = rules.classify(category: "equity", buy_date: sale_date - 2.years, sell_date: sale_date)

      [ [ short, stcg ], [ long, ltcg ] ].reject { |_, amount| amount.zero? }
    end
end
