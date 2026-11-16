# Tax-harvesting suggestions for one person's accounts.
#
# LTCG harvesting: sell long-term equity lots that are in profit so that the realized LTCG fills, but never
# exceeds, what is left of this year's Sec 112A exemption. Units come from the front of each folio's FIFO
# queue only (a lot can't be sold before the lots that were bought earlier), and fractional units are
# rounded down to 3 decimals (whole units for stocks and ETFs).
#
# Loss harvesting: the FIFO prefix of each folio whose combined unrealized result is the biggest loss.
class TaxCenter::Harvester
  FRACTIONAL_STEP = BigDecimal("0.001")

  Recommendation = Struct.new(:account, :security, :folio, :units, :cost, :proceeds, :gain, keyword_init: true)
  LossRow = Struct.new(:account, :security, :folio, :units, :cost, :proceeds, :net, :short_term, :long_term, :label, :offsets_gains, keyword_init: true)

  attr_reader :family, :date, :report

  # report: the TaxCenter::Report for the financial year containing `date`
  def initialize(family:, report:, date: Date.current, prices: {})
    @family = family
    @report = report
    @date = date
    @prices = prices
  end

  def exemption_remaining
    report.estimate.exemption_remaining
  end

  def ltcg_recommendations
    @ltcg_recommendations ||= build_ltcg_recommendations
  end

  def recommended_ltcg
    ltcg_recommendations.sum(&:gain)
  end

  def loss_rows
    @loss_rows ||= groups.filter_map { |lots| loss_row_for(lots) }.sort_by(&:net)
  end

  # Per-lot detail used by the CSV export
  def groups
    @groups ||= report.tax_lots.open_lots_by_group.values.select { |lots| price_for(lots.first.security).present? }
  end

  private
    def build_ltcg_recommendations
      remaining = exemption_remaining
      recommendations = []

      candidate_prefixes.each do |lots|
        break if remaining <= 0

        security = lots.first.security
        price = price_for(security)
        taken = []

        lots.each do |lot|
          per_unit = price - lot.cost_per_unit
          lot_gain = per_unit * lot.qty

          if lot_gain <= remaining
            taken << [ lot.qty, per_unit ]
            remaining -= lot_gain
          else
            units = floor_units((remaining / per_unit), security)
            if units.positive?
              taken << [ units, per_unit ]
              remaining -= units * per_unit
            end
            break # FIFO: nothing behind a partly sold lot can be sold
          end
        end

        next if taken.empty?

        units = taken.sum(&:first)
        gain = taken.sum { |u, per_unit| u * per_unit }
        recommendations << Recommendation.new(
          account: lots.first.account, security: security, folio: lots.first.folio,
          units: units, cost: units * price - gain, proceeds: units * price, gain: gain
        )
      end

      recommendations
    end

    # FIFO prefix of long-term equity lots that are in profit, per folio, most profitable per unit first
    def candidate_prefixes
      groups.filter_map do |lots|
        price = price_for(lots.first.security)
        prefix = lots.take_while { |lot| harvestable?(lot, price) }
        prefix.presence
      end.sort_by { |prefix| -(price_for(prefix.first.security) - prefix.first.cost_per_unit) }
    end

    def harvestable?(lot, price)
      price > lot.cost_per_unit && classification_for(lot).exemption_eligible
    end

    def loss_row_for(lots)
      price = price_for(lots.first.security)
      units = cost = 0
      short = long = BigDecimal("0")
      best = nil

      lots.each do |lot|
        classification = classification_for(lot)
        break if classification.exempt?

        pl = (price - lot.cost_per_unit) * lot.qty
        classification.term == :long ? long += pl : short += pl
        units += lot.qty
        cost += lot.cost
        net = short + long

        if net.negative? && (best.nil? || net < best[:net])
          best = { units: units, cost: cost, net: net, short: short, long: long }
        end
      end

      return nil unless best

      LossRow.new(
        account: lots.first.account, security: lots.first.security, folio: lots.first.folio,
        units: best[:units], cost: best[:cost], proceeds: best[:cost] + best[:net], net: best[:net],
        short_term: best[:short], long_term: best[:long], label: loss_label(best[:short], best[:long]),
        offsets_gains: offsets_gains?(best[:short], best[:long])
      )
    end

    def loss_label(short, long)
      if short.negative? && long.negative? then "STCL + LTCL"
      elsif short.negative? then "STCL"
      else "LTCL"
      end
    end

    # A short-term loss offsets any gain, a long-term loss only long-term gains
    def offsets_gains?(short, long)
      totals = report.estimate.totals
      short_gains = totals[:stcg_equity].positive? || totals[:slab].positive?
      long_gains = totals[:ltcg_equity].positive? || totals[:ltcg_other].positive?

      (short.negative? && (short_gains || long_gains)) || (long.negative? && long_gains)
    end

    def classification_for(lot)
      @category_cache ||= {}
      category = @category_cache.fetch(lot.security.id) { @category_cache[lot.security.id] = lot.security.effective_tax_category(family) }
      report.rules.classify(category: category, buy_date: lot.buy_date, sell_date: date)
    end

    def floor_units(units, security)
      step = security.kind_stock? || security.kind_etf? ? BigDecimal("1") : FRACTIONAL_STEP
      (units / step).floor * step
    end

    # Latest price in the family currency, or nil if there isn't one
    def price_for(security)
      return @prices[security.id] if @prices.key?(security.id)

      @prices[security.id] = begin
        money = security.current_price
        money&.exchange_to(family.currency, date: date, fallback_rate: 1)&.amount&.to_d
      end
    end
end
