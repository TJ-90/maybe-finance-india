# Imports trades from a broker's tradebook export (Zerodha Console, ...) or from the app's mutual fund
# transaction template. The layouts live in config/india_broker_presets.yml (Import::BrokerPreset).
#
# Sells have a negative quantity. Securities are matched by ISIN first, then by symbol and exchange
# (Security::Resolver). Trades that were imported before are skipped: by the broker's trade id when
# the file has one, otherwise by account, security, folio, date and quantity.
class BrokerTradebookImport < TradeImport
  include Import::InvestmentRowLookup

  # The preset is kept in column_mappings so no extra column is needed
  def broker_preset
    column_mappings&.dig("preset")
  end

  def broker_preset=(key)
    self.column_mappings = (column_mappings || {}).merge("preset" => key.presence)
  end

  # The chosen preset, or the one that fits the uploaded headers
  def preset
    Import::BrokerPreset.find(broker_preset) || detected_preset
  end

  def detected_preset
    return nil unless uploaded?

    Import::BrokerPreset.detect(csv_headers.compact)
  end

  # Defaults for the configuration form
  def preset_defaults
    return {} unless preset

    { date_format: preset.date_format, number_format: "1,234.56" }
  end

  def prepare_raw_csv(csv_str, col_sep: ",")
    self.class.strip_preamble(csv_str, col_sep: col_sep)
  end

  def generate_rows_from_csv
    rows.destroy_all

    chosen = preset
    return if chosen.nil?

    columns = chosen.resolve_columns(csv_headers.compact)
    # Exports often leave blank lines under the header; they are not trades
    data_rows = csv_rows.reject { |csv_row| csv_row.fields.all?(&:blank?) }
    mapped = data_rows.filter_map { |csv_row| chosen.row_attributes(csv_row, columns) }

    rows.insert_all!(mapped) if mapped.any?
  end

  # Mutual fund rows that name the fund but give no ISIN or scheme code (Groww). They are matched to an
  # AMFI scheme by name, and the user confirms or corrects the match on the Map step.
  def fund_names_to_resolve
    return [] unless preset&.mutual_fund?

    rows.where(exchange_operating_mic: Security::AMFI_MIC, isin: [ nil, "" ]).pluck(:ticker).uniq
        .reject { |ticker| ticker.blank? || ticker.match?(/\A\d{4,7}\z/) || ticker.upcase.match?(ISIN_PATTERN) }
  end

  def mapping_steps
    steps = super
    steps << Import::SchemeMapping if fund_names_to_resolve.any?
    steps
  end

  def required_column_keys
    %i[date ticker qty price]
  end

  def column_keys
    keys = %i[date ticker isin exchange_operating_mic qty price name]
    keys << (preset&.mutual_fund? ? :folio_number : :external_id)
    keys.unshift(:account) if account.nil?
    keys
  end

  def dry_run
    @dry_run ||= begin
      new_rows, duplicate_rows = partition_rows
      counts = { transactions: new_rows.size, already_imported: duplicate_rows.size }
      counts[:accounts] = Import::AccountMapping.for_import(self).creational.count if account.nil?
      counts
    end
  end

  def csv_template
    CSV.parse((preset || Import::BrokerPreset.find("zerodha_console")).template, headers: true)
  end

  private
    def import!
      transaction do
        mappings.each(&:create_mappable!)

        new_rows, _duplicates = partition_rows(create_securities: true)

        new_rows.each do |row, mapped_account, security|
          currency = row.currency.presence || mapped_account.currency
          amount = row.amount.presence ? row.amount.to_d : row.price.to_d * row.qty.to_d

          Trade.create!(
            security: security,
            qty: row.qty,
            price: row.price,
            currency: currency,
            folio_number: row.folio_number.presence,
            external_id: row.external_id.presence,
            entry: Entry.new(
              account: mapped_account,
              date: row.date_iso,
              amount: amount,
              name: Trade.build_name(row.qty.to_d.negative? ? "sell" : "buy", row.qty, security),
              currency: currency,
              import: self
            )
          )
        end
      end
    end

    # Returns [ [ [row, account, security], ... ], [ row, ... ] ] (new rows, rows imported before)
    def partition_rows(create_securities: false)
      reset_duplicate_tracking
      accounts_by_key = mappings.accounts.includes(:mappable).to_h { |mapping| [ mapping.key, mapping.mappable ] }
      new_rows = []
      duplicate_rows = []

      rows.ordered.each do |row|
        mapped_account = account || accounts_by_key[row.account]
        security = security_for(row, create: create_securities)

        if mapped_account && already_imported?(mapped_account, security, row)
          duplicate_rows << row
        else
          new_rows << [ row, mapped_account, security ]
        end
      end

      [ new_rows, duplicate_rows ]
    end
end
