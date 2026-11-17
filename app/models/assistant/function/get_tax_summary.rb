class Assistant::Function::GetTaxSummary < Assistant::Function
  class << self
    def name
      "get_tax_summary"
    end

    def description
      <<~INSTRUCTIONS
        Use this to get the user's realized capital gains for an Indian financial year (April 1 to March 31),
        split into short-term and long-term gains, along with the LTCG exemption used and remaining.

        Tax is per person. Pass the household member's name to see one person (their Resident or NRI status
        decides the TDS estimate); without a name it uses the person marked as the user, else the first member.

        The figures are indicative only. Surcharge, cess and loss carry-forward are not computed, so never
        present them as tax advice.
      INSTRUCTIONS
    end
  end

  def call(params = {})
    member = find_member(params["member"])
    accounts = family.accounts_with_investments.to_a
    accounts = accounts.select { |account| account.household_member_id == member.id } if member
    residency = TaxCenter::Residency.new(member: member)

    report = TaxCenter::Report.new(
      family: family,
      accounts: accounts,
      financial_year_start: financial_year_start(params["financial_year_start"]),
      slab_rate: member&.tax_slab_rate || 30,
      residency: residency
    )
    estimate = report.estimate

    {
      member: member && { name: member.name, residency_status: member.residency_label, slab_rate_percent: member.tax_slab_rate },
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
      indicative_tax_at_slab_rate: money(estimate.tax),
      estimated_tds_deducted_for_nri: residency.nri? ? money(report.tds_total) : nil,
      sales_count: report.redemption_rows.size,
      disclaimer: "Indicative only. Surcharge, cess, loss carry-forward and the 87A rebate are not computed. This is not tax advice."
    }
  end

  def params_schema
    build_schema(
      required: [ "financial_year_start", "member" ],
      properties: {
        member: {
          type: [ "string", "null" ],
          description: "Name of the household member to report on. Pass null for the default person."
        },
        financial_year_start: {
          type: [ "string", "null" ],
          description: "Any date inside the financial year to report on, in YYYY-MM-DD format. Pass null for the current financial year."
        }
      }
    )
  end

  private
    def find_member(name)
      members = family.household_members.ordered.to_a
      return nil if members.empty?

      members.find { |member| name.present? && member.name.casecmp?(name.to_s.strip) } ||
        members.find { |member| member.id == user.household_member_id } ||
        members.find(&:myself?) || members.first
    end

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
