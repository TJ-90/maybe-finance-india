class Assistant::Function::GetTaxSummary < Assistant::Function
  class << self
    def name
      "get_tax_summary"
    end

    def description
      <<~INSTRUCTIONS
        Use this to get the user's realized capital gains for an Indian financial year (April 1 to March 31),
        split into short-term and long-term gains, along with the LTCG exemption used and remaining.

        The figures are indicative only. Surcharge, cess and loss carry-forward are not computed, so never
        present them as tax advice.
      INSTRUCTIONS
    end
  end

  def call(params = {})
    report = TaxCenter::Report.new(
      family: family,
      accounts: family.accounts_with_investments.to_a,
      financial_year_start: financial_year_start(params["financial_year_start"])
    )
    estimate = report.estimate

    {
      financial_year: report.label,
      period_start: report.period.start_date,
      period_end: report.period.end_date,
      currency: family.currency,
      realized_gains: {
        equity_short_term: money(estimate.totals[:stcg_equity]),
        equity_long_term: money(estimate.totals[:ltcg_equity]),
        other_taxed_at_slab: money(estimate.totals[:slab]),
        other_long_term: money(estimate.totals[:ltcg_other]),
        exempt: money(estimate.totals[:exempt]),
        total: money(estimate.total_gain)
      },
      ltcg_equity_exemption: {
        limit: money(estimate.exemption_limit),
        used: money(estimate.exemption_used),
        remaining: money(estimate.exemption_remaining)
      },
      indicative_tax_at_30_percent_slab: money(estimate.tax),
      sales_count: report.redemption_rows.size,
      disclaimer: "Indicative only. Surcharge, cess, loss carry-forward and the 87A rebate are not computed. This is not tax advice."
    }
  end

  def params_schema
    build_schema(
      required: [ "financial_year_start" ],
      properties: {
        financial_year_start: {
          type: [ "string", "null" ],
          description: "Any date inside the financial year to report on, in YYYY-MM-DD format. Pass null for the current financial year."
        }
      }
    )
  end

  private
    def financial_year_start(value)
      date = value.present? ? Date.iso8601(value.to_s) : Date.current
      Period.financial_year_start(date)
    rescue ArgumentError
      Period.financial_year_start(Date.current)
    end

    def money(amount)
      Money.new(amount, family.currency).format
    end
end
