# Turns the text of a CAMS / KFintech consolidated account statement (CAS) into plain data:
#
#   investors -> folios -> schemes -> transactions
#
# It works on text only (the PDF is turned into text by CasImport::PdfText), so it can be tested
# with synthetic .txt fixtures. Only the masked PAN (XXXXX1234X) is ever kept.
#
# The layouts handled here are written from public descriptions of the CAMS and KFintech
# statements, not from real files. Each line is matched on its own, so unknown lines are ignored
# and anything that looks like a transaction but can't be read ends up in `warnings`.
#
#   Detailed CAS
#     Name: / PAN:                          investor
#     <AMC> Mutual Fund                     AMC heading
#     Folio No: 1234567 / 89                folio
#     <name> - ISIN: INF...(Advisor: ...)   scheme
#     Opening Unit Balance: 100.000
#     12-Jan-2024 Purchase 5,000.00 50.123 99.75 150.123    date, description, amount, units, NAV, balance
#     Closing Unit Balance: 150.123  NAV on 31-Mar-2024: INR 120.50  Total Cost Value: ...  Market Value on ...: INR ...
#
#   Summary CAS
#     <folio> <ISIN> <scheme> <cost value> <units> <NAV date> <NAV> <market value> [registrar]
class CasImport::Parser
  DATE = /\d{1,2}-[A-Za-z]{3}-\d{4}/
  # Statements always print units, NAVs and amounts with decimals; requiring them keeps counters
  # such as "Instalment 3" in a description from being read as a column
  NUMBER = /\(?-?[\d,]+\.\d+\)?/
  PAN = /\b([A-Z]{5})(\d{4})([A-Z])\b/
  ISIN = /INF[0-9A-Z]{9}/

  # Transaction types that make a Trade, and which way the units move
  BUY_TYPES = %w[purchase sip switch_in idcw_reinvest bonus].freeze
  SELL_TYPES = %w[redemption switch_out].freeze
  TRADE_TYPES = (BUY_TYPES + SELL_TYPES + %w[reversal]).freeze

  Result = Struct.new(:statement_type, :period_from, :period_to, :as_on, :investors, :warnings, keyword_init: true) do
    def summary?
      statement_type == "summary"
    end

    def schemes
      investors.flat_map { |investor| investor[:folios] }.flat_map { |folio| folio[:schemes] }
    end

    def transactions
      schemes.flat_map { |scheme| scheme[:transactions] }
    end

    def as_json(*)
      to_h.as_json
    end
  end

  class << self
    def parse(text)
      new(text).parse
    end

    # Units with the sign a Trade needs: buys positive, redemptions and switch-outs negative
    def signed_units(transaction)
      units = transaction[:units]
      return BigDecimal("0") if units.nil?

      magnitude = units.abs

      case transaction[:type]
      when *BUY_TYPES then magnitude
      when *SELL_TYPES then -magnitude
      when "reversal"
        # Reversing a redemption or switch-out gives the units back
        transaction[:description].to_s.match?(/redemption|redeem|switch.{0,8}out/i) ? magnitude : -magnitude
      else BigDecimal("0")
      end
    end

    # XXXXX1234X: the digits are all that survive of a PAN
    def mask_pan(pan)
      match = pan.to_s.upcase.match(PAN)
      match ? "XXXXX#{match[2]}X" : nil
    end

    def parse_number(str)
      return nil if str.blank?

      negative = str.include?("(") || str.strip.start_with?("-")
      value = BigDecimal(str.gsub(/[^\d.]/, "").presence || "0")
      negative ? -value : value
    end

    def parse_date(str)
      Date.strptime(str, "%d-%b-%Y")
    rescue ArgumentError
      nil
    end
  end

  def initialize(text)
    @lines = text.to_s.each_line.map { |line| line.gsub(/\s+/, " ").strip }.reject(&:blank?)
    @investors = []
    @warnings = []
  end

  def parse
    @lines.each { |line| consume(line) }
    finish_scheme

    @investors.each do |investor|
      investor[:folios].each { |folio| folio[:schemes].each { |scheme| verify_units(scheme, investor) } }
    end

    summary = transaction_count.zero? && schemes_count.positive?

    Result.new(
      statement_type: summary ? "summary" : "detailed",
      period_from: @period_from,
      period_to: @period_to,
      as_on: @as_on || @period_to,
      investors: @investors.reject { |investor| investor[:folios].empty? },
      warnings: @warnings
    )
  end

  private
    def consume(line)
      return if consume_header(line)
      return if consume_investor(line)
      return if consume_amc(line)
      return if consume_folio(line)
      return if consume_summary_row(line)
      return if consume_scheme(line)
      return if consume_balances(line)

      consume_transaction(line)
    end

    # --- statement header ---

    def consume_header(line)
      if (match = line.match(/(#{DATE})\s+to\s+(#{DATE})/i))
        @period_from = self.class.parse_date(match[1])
        @period_to = self.class.parse_date(match[2])
        return true
      end

      if (match = line.match(/\bas on\s+(#{DATE})/i)) && !line.match?(/unit balance|NAV/i)
        @as_on = self.class.parse_date(match[1])
        return true
      end

      false
    end

    # --- investor ---

    def consume_investor(line)
      if (match = line.match(/\A(?:investor )?name\s*:\s*(.+)\z/i))
        @pending_name = match[1].strip
        @current_investor = nil
        return true
      end

      if !line.match?(/\Afolio/i) && (match = line.match(/\bPAN\s*:\s*(#{PAN.source})/))
        investor_for(match[1])
        return true
      end

      false
    end

    def investor_for(pan_text)
      masked = pan_text ? self.class.mask_pan(pan_text) : nil

      if masked
        @current_investor = @investors.find { |investor| investor[:pan_masked] == masked } ||
                            new_investor(masked)
      else
        @current_investor ||= @investors.find { |investor| investor[:name] == @pending_name } || new_investor(nil)
      end
    end

    def new_investor(masked)
      investor = { name: @pending_name.presence || "Investor", pan_masked: masked, folios: [] }
      @investors << investor
      investor
    end

    # --- AMC and folio ---

    def consume_amc(line)
      return false unless line.match?(/\A[A-Za-z0-9&.' -]+(?:Mutual Fund|Mutual Funds)\z/i)
      return false if line.match?(/ISIN|Folio/i)

      @current_amc = line.strip
      true
    end

    def consume_folio(line)
      match = line.match(%r{\Afolio no\.?\s*:?\s*([0-9A-Za-z]+(?:\s*/\s*[0-9A-Za-z]+)?)}i)
      return false unless match

      finish_scheme

      pan = line[/\bPAN\s*:\s*(#{PAN.source})/, 1]
      investor = investor_for(pan)
      folio_number = match[1].gsub(/\s+/, "")

      @current_folio = investor[:folios].find { |folio| folio[:folio_number] == folio_number } ||
                       { amc: @current_amc, folio_number: folio_number, schemes: [] }
      investor[:folios] << @current_folio unless investor[:folios].include?(@current_folio)
      @current_investor = investor
      true
    end

    # --- schemes ---

    def consume_scheme(line)
      match = line.match(/ISIN\s*:\s*(#{ISIN.source})/i)
      return false unless match
      return false if line.match?(/\A#{DATE}/)

      finish_scheme
      ensure_folio!

      name_part = line[0...match.begin(0)].sub(/\A(?:scheme(?: name)?)\s*:\s*/i, "").sub(/\s*-\s*\z/, "").strip
      amc_code = nil

      # CAMS prefixes the scheme with its own internal code, e.g. "P8046-Some Fund - Direct Growth"
      if (code_match = name_part.match(/\A([A-Za-z0-9]*\d[A-Za-z0-9]*)\s*-\s*(.+)\z/))
        amc_code = code_match[1]
        name_part = code_match[2].strip
      end

      @current_scheme = {
        name: name_part,
        isin: match[1],
        amc_code: amc_code,
        amfi_code: line[/\bAMFI(?: code)?\s*:\s*(\d{4,7})/i, 1],
        registrar: line[/Registrar\s*:\s*([A-Za-z]+)/i, 1]&.upcase,
        advisor: line[/Advisor\s*:\s*([^)]+)\)/i, 1]&.strip,
        opening_units: nil,
        closing_units: nil,
        nav: nil,
        nav_date: nil,
        cost_value: nil,
        market_value: nil,
        transactions: []
      }
      @current_folio[:schemes] << @current_scheme
      true
    end

    # Summary CAS: one row per scheme
    def consume_summary_row(line)
      pattern = /\A([0-9A-Za-z]+(?:\s*\/\s*[0-9A-Za-z]+)?)\s+(#{ISIN.source})\s+(.+?)\s+(#{NUMBER.source})\s+(#{NUMBER.source})\s+(#{DATE})\s+(#{NUMBER.source})\s+(#{NUMBER.source})(?:\s+([A-Za-z]+))?\z/
      match = line.match(pattern)
      return false unless match

      finish_scheme
      investor = investor_for(nil)
      folio_number = match[1].gsub(/\s+/, "")
      folio = investor[:folios].find { |item| item[:folio_number] == folio_number }

      unless folio
        folio = { amc: @current_amc, folio_number: folio_number, schemes: [] }
        investor[:folios] << folio
      end

      nav_date = self.class.parse_date(match[6])
      folio[:schemes] << {
        name: match[3].strip, isin: match[2], amc_code: nil, amfi_code: nil, registrar: match[9]&.upcase, advisor: nil,
        opening_units: nil,
        closing_units: self.class.parse_number(match[5]),
        nav: self.class.parse_number(match[7]),
        nav_date: nav_date,
        cost_value: self.class.parse_number(match[4]),
        market_value: self.class.parse_number(match[8]),
        transactions: []
      }
      @as_on ||= nav_date
      true
    end

    def ensure_folio!
      return if @current_folio

      investor = investor_for(nil)
      @current_folio = { amc: @current_amc, folio_number: "UNKNOWN", schemes: [] }
      investor[:folios] << @current_folio
    end

    def finish_scheme
      @current_scheme = nil
    end

    # --- balances ---

    def consume_balances(line)
      return false unless @current_scheme

      matched = false

      if (match = line.match(/opening unit balance\s*:\s*(#{NUMBER.source})/i))
        @current_scheme[:opening_units] = self.class.parse_number(match[1])
        matched = true
      end

      if (match = line.match(/closing unit balance\s*:\s*(#{NUMBER.source})/i))
        @current_scheme[:closing_units] = self.class.parse_number(match[1])
        matched = true
      end

      if (match = line.match(/NAV on (#{DATE})\s*:\s*(?:INR|Rs\.?|₹)?\s*(#{NUMBER.source})/i))
        @current_scheme[:nav_date] = self.class.parse_date(match[1])
        @current_scheme[:nav] = self.class.parse_number(match[2])
        matched = true
      end

      if (match = line.match(/total cost value\s*:\s*(?:INR|Rs\.?|₹)?\s*(#{NUMBER.source})/i))
        @current_scheme[:cost_value] = self.class.parse_number(match[1])
        matched = true
      end

      if (match = line.match(/market value on (#{DATE})\s*:\s*(?:INR|Rs\.?|₹)?\s*(#{NUMBER.source})/i))
        @current_scheme[:market_value] = self.class.parse_number(match[2])
        matched = true
      end

      matched
    end

    # --- transactions ---

    def consume_transaction(line)
      match = line.match(/\A(#{DATE})\s+(.+?)\s+((?:#{NUMBER.source}\s*)+)\z/)
      return unless match

      date = self.class.parse_date(match[1])
      description = match[2].strip
      numbers = match[3].split.map { |token| self.class.parse_number(token) }

      if @current_scheme.nil?
        @warnings << "Ignored a transaction outside any scheme: #{line.truncate(80)}"
        return
      end

      if description.match?(/\*{3}/)
        attach_charge(date, description, numbers.first)
        return
      end

      transactions = @current_scheme[:transactions]
      type = classify(description)

      case numbers.size
      when 4
        amount, units, nav, balance = numbers
      when 1
        # Cash-only lines, such as an IDCW payout
        amount = numbers.first
        units = nav = balance = nil
      else
        @warnings << "Could not read this transaction line: #{line.truncate(80)}"
        return
      end

      @warnings << "Skipped a line with an unrecognised type: #{line.truncate(80)}" if type == "unknown"

      transactions << {
        date: date,
        description: description,
        type: type,
        units: units,
        amount: amount,
        nav: nav,
        balance: balance,
        stamp_duty: nil,
        stt: nil
      }
    end

    # "*** Stamp Duty ***" / "*** STT Paid ***" belong to the transaction above them
    def attach_charge(date, description, amount)
      parent = @current_scheme[:transactions].reverse.find { |transaction| transaction[:date] == date } ||
               @current_scheme[:transactions].last

      if parent.nil?
        @warnings << "Ignored a charge line with no transaction above it: #{description}"
        return
      end

      key = description.match?(/stt/i) ? :stt : :stamp_duty
      parent[key] = (parent[key] || 0) + amount.to_d.abs
    end

    def classify(description)
      text = description.downcase

      return "reversal" if text.match?(/revers|reject|cancel/)
      return "idcw_payout" if text.match?(/(dividend|idcw|income distribution).*(payout|paid|pay out)|(payout|paid).*(dividend|idcw)/) && !text.match?(/reinvest/)
      return "idcw_reinvest" if text.match?(/(dividend|idcw|income distribution).*reinvest|reinvest/)
      return "switch_out" if text.match?(/switch.{0,8}out|lateral shift out/)
      return "switch_in" if text.match?(/switch.{0,8}in\b|lateral shift in/)
      return "redemption" if text.match?(/redemption|redeem|withdrawal/)
      return "sip" if text.match?(/systematic|\bsip\b|instalment|installment/)
      return "bonus" if text.match?(/\bbonus\b/)
      return "purchase" if text.match?(/purchase|nfo|subscription|additional|new fund offer/)

      "unknown"
    end

    # --- checks ---

    def transaction_count
      @investors.sum { |investor| investor[:folios].sum { |folio| folio[:schemes].sum { |scheme| scheme[:transactions].size } } }
    end

    def schemes_count
      @investors.sum { |investor| investor[:folios].sum { |folio| folio[:schemes].size } }
    end

    # Opening units plus the units of every transaction must give the closing units. A mismatch means
    # a line was missed or misread, so the user is told to check before importing.
    def verify_units(scheme, investor)
      return if scheme[:transactions].empty?
      return if scheme[:closing_units].nil?

      opening = scheme[:opening_units] || 0
      movement = scheme[:transactions].sum(BigDecimal("0")) { |transaction| CasImport::Parser.signed_units(transaction) }
      difference = (opening + movement - scheme[:closing_units]).abs

      return if difference <= BigDecimal("0.001")

      @warnings << "Units for #{scheme[:name]} (#{investor[:pan_masked] || investor[:name]}) don't add up: transactions give #{(opening + movement).to_s('F')}, statement says #{scheme[:closing_units].to_s('F')}."
    end
end
