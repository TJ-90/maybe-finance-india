# Backs the tax calculator form: which folio holdings can be sold, and the simulated sale for the chosen one.
class TaxCenter::Calculation
  Option = Struct.new(:value, :label, :units, keyword_init: true)

  attr_reader :report, :inputs

  # inputs: holding ("account_id|security_id|folio"), units, sale_date, price, only_held_over_months,
  #         realized_stcg, realized_ltcg (strings from the form)
  def initialize(report:, inputs: {})
    @report = report
    @inputs = inputs.to_h.with_indifferent_access
  end

  def options
    @options ||= lots_by_group.map do |key, lots|
      first = lots.first
      folio = first.folio.present? ? " (folio #{first.folio})" : ""
      Option.new(
        value: key.join("|"),
        label: "#{first.security.display_name}#{folio} in #{first.account.name}",
        units: lots.sum(&:qty)
      )
    end.sort_by(&:label)
  end

  def selected_lots
    @selected_lots ||= lots_by_group.find { |key, _| key.join("|") == inputs[:holding] }&.last || []
  end

  def sale_date
    @sale_date ||= parse_date(inputs[:sale_date]) || Date.current
  end

  def price
    return BigDecimal(inputs[:price].to_s) if inputs[:price].present? && decimal?(inputs[:price])

    default_price
  end

  # Latest known price of the selected security, in the family currency
  def default_price
    security = selected_lots.first&.security
    money = security&.current_price
    money&.exchange_to(report.family.currency, fallback_rate: 1)&.amount&.to_d
  end

  def requested?
    selected_lots.any? && decimal?(inputs[:units]) && BigDecimal(inputs[:units].to_s).positive? && price.present?
  end

  def simulator
    return nil unless requested?

    @simulator ||= TaxCenter::SaleSimulator.new(
      family: report.family,
      lots: selected_lots,
      units: inputs[:units],
      sale_date: sale_date,
      price: price,
      slab_rate: report.slab_rate,
      realized_stcg: decimal_or_zero(inputs[:realized_stcg]),
      realized_ltcg: decimal_or_zero(inputs[:realized_ltcg]),
      only_held_over_months: inputs[:only_held_over_months].presence,
      rules: report.rules
    )
  end

  # Already-realized equity gains this financial year, used to prefill the form
  def default_realized(bucket)
    total = report.estimate.totals[bucket]
    total.positive? ? total.round(2).to_s("F") : ""
  end

  private
    def lots_by_group
      @lots_by_group ||= report.tax_lots.open_lots_by_group
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def decimal?(value)
      BigDecimal(value.to_s)
      true
    rescue ArgumentError, TypeError
      false
    end

    def decimal_or_zero(value)
      decimal?(value) && value.present? ? BigDecimal(value.to_s) : BigDecimal("0")
    end
end
