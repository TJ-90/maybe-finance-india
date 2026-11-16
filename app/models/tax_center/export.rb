require "csv"

# CSV downloads for the Tax Center. Amounts are plain decimals in the family currency.
class TaxCenter::Export
  def initialize(report:, harvester: nil)
    @report = report
    @harvester = harvester
  end

  def realized_gains_csv
    CSV.generate do |csv|
      csv << [ "Financial year", "Account", "Scheme / security", "Folio", "Sell date", "Units", "Proceeds", "Cost", "Net gain", "Short-term gain", "Long-term gain" ]

      @report.redemption_rows.each do |row|
        redemption = row.redemption
        csv << [
          @report.label, text(redemption.account.name), text(redemption.security.display_name), text(redemption.folio),
          redemption.date.iso8601, number(redemption.qty), money(redemption.proceeds), money(redemption.cost),
          money(row.gain), money(row.short_term_gain), money(row.long_term_gain)
        ]
      end
    end
  end

  def harvesting_csv
    CSV.generate do |csv|
      csv << [ "Type", "Account", "Scheme / security", "Folio", "Units to sell", "Proceeds", "Cost", "Gain / loss", "Label" ]

      @harvester.ltcg_recommendations.each do |rec|
        csv << [ "LTCG harvest", text(rec.account.name), text(rec.security.display_name), text(rec.folio), number(rec.units),
                 money(rec.proceeds), money(rec.cost), money(rec.gain), "LTCG" ]
      end

      @harvester.loss_rows.each do |row|
        csv << [ "Loss harvest", text(row.account.name), text(row.security.display_name), text(row.folio), number(row.units),
                 money(row.proceeds), money(row.cost), money(row.net), row.label ]
      end
    end
  end

  private
    # Stop spreadsheet apps from treating text as a formula
    def text(value)
      value.to_s.match?(/\A[=+\-@\t\r]/) ? "'#{value}" : value
    end

    def money(value)
      value.to_d.round(2).to_s("F")
    end

    def number(value)
      value.to_d.round(3).to_s("F")
    end
end
