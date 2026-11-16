# Imports mutual fund holdings and transactions from a CAMS / KFintech consolidated account
# statement (CAS) PDF.
#
# Privacy: the PDF and its password are only used inside the upload request (see #load_pdf!). What
# is stored is the text-derived statement data with PANs masked (XXXXX1234X), as import rows. The
# publish job only ever receives this import record.
class CasImport < Import
  include Import::InvestmentRowLookup

  Error = Class.new(StandardError)
  NoStatementError = Class.new(Error)

  ACCOUNT_SUBTYPE = "mutual_fund".freeze
  ROW_DATE_FORMAT = "%Y-%m-%d".freeze
  CURRENCY = "INR".freeze

  TYPE_LABELS = {
    "purchase" => "Purchase",
    "sip" => "SIP",
    "switch_in" => "Switch in",
    "switch_out" => "Switch out",
    "redemption" => "Redemption",
    "idcw_reinvest" => "IDCW reinvested",
    "bonus" => "Bonus units",
    "reversal" => "Reversal",
    "opening_position" => "Opening position"
  }.freeze

  # Reads the statement PDF and stores its rows. The file and the password stay in memory.
  def load_pdf!(file, password: nil)
    raise NoStatementError, "Choose the statement PDF to upload." if file.blank?

    load_text!(PdfText.extract(file, password: password))
  end

  # Parses already-extracted statement text (see CasImport::Parser) and replaces this import's rows
  def load_text!(text)
    result = Parser.parse(text)

    if result.investors.empty? || result.schemes.empty?
      raise NoStatementError, "We couldn't find any mutual fund holdings in this statement. Please upload a detailed or summary CAS from CAMS or KFintech."
    end

    transaction do
      update!(
        raw_file_str: JSON.generate(result.as_json),
        date_format: ROW_DATE_FORMAT,
        number_format: "1,234.56",
        signage_convention: "inflows_positive"
      )

      rows.destroy_all
      rows.insert_all!(row_attributes(result))
      reload
      sync_mappings
    end

    self
  end

  # Statement as stored: investors (masked PAN), folios, schemes, warnings
  def statement
    @statement ||= raw_file_str.present? ? JSON.parse(raw_file_str).with_indifferent_access : nil
  end

  def summary_statement?
    statement.present? && statement[:statement_type] == "summary"
  end

  def statement_warnings
    Array(statement&.dig(:warnings))
  end

  def investors
    Array(statement&.dig(:investors))
  end

  def csv_based?
    false
  end

  def mapping_steps
    [ Import::AccountMapping ]
  end

  def required_column_keys
    %i[date ticker qty price]
  end

  def column_keys
    %i[account date ticker folio_number qty price name]
  end

  def csv_template
    raise NotImplementedError, "CAS imports read a PDF statement"
  end

  def dry_run
    @dry_run ||= begin
      new_rows, duplicate_rows = partition_rows

      {
        new_trades: new_rows.size,
        already_imported: duplicate_rows.size,
        accounts: Import::AccountMapping.for_import(self).creational.count
      }
    end
  end

  # Used by Import::AccountMapping when "Add as new account" is chosen for a statement investor
  def create_investor_account!(name)
    family.accounts.create_or_find_by!(name: name) do |account|
      account.balance = 0
      account.cash_balance = 0
      account.currency = CURRENCY
      account.accountable = Investment.new
      account.subtype = ACCOUNT_SUBTYPE
      account.import = self
    end
  end

  def investment_account_scope
    family.accounts.where(accountable_type: "Investment")
  end

  def max_row_count
    20000
  end

  private
    def import!
      transaction do
        mappings.each(&:create_mappable!)

        new_rows, _duplicates = partition_rows(create_securities: true)

        new_rows.each do |row, account, security|
          currency = row.currency.presence || account.currency

          Trade.create!(
            security: security,
            qty: row.qty,
            price: row.price,
            currency: currency,
            folio_number: row.folio_number.presence,
            entry: Entry.new(
              account: account,
              date: row.date_iso,
              amount: row.amount,
              name: row.name,
              currency: currency,
              import: self
            )
          )
        end
      end
    end

    # Splits the rows into those that will become trades and those that match a trade imported before
    # (same account, security, folio, date and quantity).
    #
    # Returns [ [ [row, account, security], ... ], [ row, ... ] ]
    def partition_rows(create_securities: false)
      reset_duplicate_tracking
      accounts_by_key = mappings.accounts.includes(:mappable).to_h { |mapping| [ mapping.key, mapping.mappable ] }
      new_rows = []
      duplicate_rows = []

      rows.ordered.each do |row|
        account = accounts_by_key[row.account]
        security = security_for(row, create: create_securities)

        if account && already_imported?(account, security, row)
          duplicate_rows << row
        else
          new_rows << [ row, account, security ]
        end
      end

      [ new_rows, duplicate_rows ]
    end

    def row_attributes(result)
      names = account_names_by_investor(result)

      result.investors.flat_map do |investor|
        account_name = names.fetch(investor)

        investor[:folios].flat_map do |folio|
          folio[:schemes].flat_map do |scheme|
            if result.summary?
              [ summary_row(account_name, folio, scheme, result.as_on) ].compact
            else
              [ opening_row(account_name, folio, scheme, result.period_from) ].compact +
                scheme[:transactions].filter_map { |transaction| transaction_row(account_name, folio, scheme, transaction) }
            end
          end
        end
      end
    end

    def transaction_row(account_name, folio, scheme, transaction)
      return nil unless Parser::TRADE_TYPES.include?(transaction[:type])

      qty = Parser.signed_units(transaction)
      return nil if qty.zero?

      amount = transaction[:amount].to_d.abs
      price = transaction[:nav].presence || (amount / qty.abs)
      notes = [ transaction[:description] ]
      notes << "Stamp duty #{transaction[:stamp_duty].to_d.to_s('F')}" if transaction[:stamp_duty]
      notes << "STT #{transaction[:stt].to_d.to_s('F')}" if transaction[:stt]

      base_row(account_name, folio, scheme).merge(
        date: transaction[:date].iso8601,
        qty: qty.to_s("F"),
        price: price.to_d.to_s("F"),
        amount: (qty.positive? ? amount : -amount).to_s("F"),
        name: "#{TYPE_LABELS.fetch(transaction[:type])}: #{scheme[:name]}".truncate(120),
        entity_type: transaction[:type],
        notes: notes.join(" | ")
      )
    end

    # Units held before the statement period begins. Without this the imported units would fall short of
    # the closing balance. The price is the scheme's average cost per unit, so it is approximate.
    def opening_row(account_name, folio, scheme, period_from)
      units = scheme[:opening_units].to_d
      return nil unless units.positive?

      date = period_from || scheme[:transactions].filter_map { |transaction| transaction[:date] }.min&.prev_day
      return nil unless date

      closing = scheme[:closing_units].to_d
      price = if scheme[:cost_value].to_d.positive? && closing.positive?
        (scheme[:cost_value].to_d / closing).round(4)
      else
        scheme[:transactions].filter_map { |transaction| transaction[:nav] }.first.to_d
      end

      base_row(account_name, folio, scheme).merge(
        date: date.iso8601,
        qty: units.to_s("F"),
        price: price.to_s("F"),
        amount: (units * price).round(2).to_s("F"),
        name: "#{TYPE_LABELS.fetch('opening_position')}: #{scheme[:name]}".truncate(120),
        entity_type: "opening_position",
        notes: "Units held before the statement period; price is the average cost, so XIRR and tax lots are approximate"
      )
    end

    # A summary CAS has no history: one opening position per scheme, at cost
    def summary_row(account_name, folio, scheme, as_on)
      units = scheme[:closing_units].to_d
      return nil unless units.positive? && as_on

      cost = scheme[:cost_value].to_d
      cost = scheme[:market_value].to_d if cost.zero?

      base_row(account_name, folio, scheme).merge(
        date: as_on.iso8601,
        qty: units.to_s("F"),
        price: (cost / units).round(4).to_s("F"),
        amount: cost.to_s("F"),
        name: "#{TYPE_LABELS.fetch('opening_position')}: #{scheme[:name]}".truncate(120),
        entity_type: "opening_position",
        notes: "Summary statement: no transaction history, so XIRR and tax lots are approximate"
      )
    end

    def base_row(account_name, folio, scheme)
      {
        account: account_name,
        ticker: scheme[:amfi_code].presence || scheme[:isin],
        isin: scheme[:isin],
        folio_number: folio[:folio_number],
        currency: CURRENCY,
        exchange_operating_mic: Security::AMFI_MIC,
        category: "",
        tags: ""
      }
    end

    # "Mutual Funds – Asha". Investors who share a first name get their PAN digits added.
    def account_names_by_investor(result)
      base = result.investors.to_h { |investor| [ investor, "Mutual Funds – #{first_name(investor[:name])}" ] }

      base.to_h do |investor, name|
        shared = base.values.count(name) > 1
        digits = investor[:pan_masked].to_s[/\d{4}/]
        [ investor, shared && digits ? "#{name} (#{digits})" : name ]
      end
    end

    def first_name(full_name)
      full_name.to_s.split.first.to_s.downcase.capitalize.presence || "Investor"
    end
end
