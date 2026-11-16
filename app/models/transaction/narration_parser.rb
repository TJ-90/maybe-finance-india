# Parses the free-text "narration" that Indian banks put on every statement line
# (UPI, NEFT, IMPS, RTGS, NACH/ACH, card, ATM, cheque ...) into structured fields.
#
#   Transaction::NarrationParser.parse("UPI-SWIGGY-swiggy@icici-ICIC0000001-412345678901-UPI")
#   # => { payment_mode: "upi", counterparty: "Swiggy", vpa: "swiggy@icici",
#   #      reference_number: "412345678901", clean_name: "Swiggy" }
#
# Banks do not publish these formats and they change without notice, so the parser is
# deliberately conservative: anything it does not recognise returns all-nil fields and the
# caller keeps the original narration.
class Transaction::NarrationParser
  EMPTY = { payment_mode: nil, counterparty: nil, vpa: nil, reference_number: nil, clean_name: nil }.freeze

  VPA_REGEX = /[\w.+]{2,}@[a-z][a-z0-9]{1,}/i
  VPA_PLACEHOLDER = "VPAPLACEHOLDER".freeze
  IFSC_REGEX = /\A[A-Z]{4}0[A-Z0-9]{6}\z/i
  CARD_MASK_REGEX = /\b\d{4,6}[Xx*]{4,8}\d{2,4}\b/
  # A bank/UTR reference: 10+ digits, or a 10+ char alphanumeric with at least six digits (HDFCN52024010112345).
  REFERENCE_REGEX = /\A(?=[A-Z0-9]*\d{6})[A-Z0-9]{10,}\z/i
  # Tokens that are structure, never a counterparty.
  NOISE_TOKENS = %w[UPI DR CR D C P2A P2M MF TP NEFT IMPS RTGS NACH ACH ECS MMT IB INB TRANSFER NETBANK PAYMENT].freeze
  ACRONYMS = %w[BSE NSE ICCL LIC HDFC ICICI SBI IRCTC BESCOM NPCI AMC SIP EMI LLP IDFC UPI HUF].freeze

  CHARGES_REGEX = /\b(?:CHGS?|CHARGES?|CHRGS?|ANNUAL\s+FEE|FEES?|GST|SERVICE\s+TAX|PENALTY|SMS\s+ALERT|MIN(?:IMUM)?\s+BAL(?:ANCE)?)\b/i
  STRUCTURED_CHANNEL_REGEX = /\A(?:NEFT|IMPS|RTGS|NACH|ACH|ECS)(?:\s+[CD]R?)?\s*[-\/*:]/i

  def self.parse(narration)
    new(narration).parse
  end

  def initialize(narration)
    @raw = narration.to_s.gsub(/\s+/, " ").strip
  end

  def parse
    return EMPTY.dup if @raw.blank?

    text = strip_prefixes(@raw)

    parse_interest(text) ||
      parse_upi(text) ||
      parse_charges(text) ||
      parse_bank_transfer(text) ||
      parse_nach(text) ||
      parse_atm(text) ||
      parse_card(text) ||
      parse_cheque(text) ||
      parse_cash(text) ||
      EMPTY.dup
  end

  private
    def strip_prefixes(text)
      text.sub(/\A(?:TO|BY)\s+TRANSFER\s*[-\s]*/i, "").sub(/\A(?:MMT|INB|IB)\s*[\/-]\s*/i, "")
    end

    def parse_interest(text)
      return unless text.match?(/\A(?:INT\.?\s*PD|INTEREST\s+(?:PAID|CREDIT|CAPITALI[SZ]ED)|CREDIT\s+INTEREST|INT\.?\s*CREDIT)/i)

      result(payment_mode: "other", clean_name: "Interest credit")
    end

    def parse_charges(text)
      return if text.match?(STRUCTURED_CHANNEL_REGEX) || text.match?(CARD_MASK_REGEX)
      return unless text.match?(CHARGES_REGEX)

      result(payment_mode: "other", clean_name: "Bank charges")
    end

    def parse_upi(text)
      return unless text.match?(/\AUPI\b/i)

      vpa = text[VPA_REGEX]
      tokens = tokenize(text.sub(VPA_REGEX, VPA_PLACEHOLDER))
      counterparty = pick_counterparty(tokens)

      result(
        payment_mode: "upi",
        counterparty: counterparty,
        vpa: vpa&.downcase,
        reference_number: pick_reference(tokens),
        clean_name: counterparty || "UPI payment"
      )
    end

    def parse_bank_transfer(text)
      mode = text[/\A(NEFT|IMPS|RTGS)\b/i]&.downcase
      return unless mode

      tokens = tokenize(text)
      counterparty = pick_counterparty(tokens)

      result(
        payment_mode: mode,
        counterparty: counterparty,
        reference_number: pick_reference(tokens),
        clean_name: counterparty || "#{mode.upcase} transfer"
      )
    end

    def parse_nach(text)
      return unless text.match?(/\A(?:NACH|ACH|ECS)\b/i)

      tokens = tokenize(text.gsub(/\bTP\s+ACH\b/i, ""))
      counterparty = pick_counterparty(tokens)

      result(
        payment_mode: "nach",
        counterparty: counterparty,
        reference_number: pick_reference(tokens),
        clean_name: counterparty || "NACH debit"
      )
    end

    def parse_atm(text)
      return unless text.match?(/\A(?:ATW|NWD|EAW|ATM|CASH\s+WDL|CASH\s+WITHDRAWAL)\b/i)

      result(payment_mode: "atm", clean_name: "ATM withdrawal")
    end

    def parse_card(text)
      return unless text.match?(/\A(?:POS|PUR|PCD|ECOM|DEBIT\s+CARD|CARD)\b/i)

      remainder = text.sub(/\A(?:POS|PUR|PCD|ECOM(?:\s+PUR)?|DEBIT\s+CARD|CARD)\b\s*/i, "").gsub(CARD_MASK_REGEX, " ").strip
      tokens = tokenize(remainder)
      tokens = [ remainder ] if tokens.size <= 1
      counterparty = pick_counterparty([ nil, *tokens.map { |t| t.sub(/\s+\d{4,}\z/, "") } ])

      result(
        payment_mode: "card",
        counterparty: counterparty,
        reference_number: pick_reference(tokens),
        clean_name: counterparty || "Card payment"
      )
    end

    def parse_cheque(text)
      return unless text.match?(/\A(?:CHQ|CHEQUE|CLG|CLEARING)\b/i)

      number = text[/(?<!\d)\d{6}(?!\d)/]
      label = if text.match?(/\bDEP/i)
        "Cheque deposit"
      elsif text.match?(/\b(?:PAID|ISSUED)\b/i)
        "Cheque payment"
      else
        "Cheque"
      end

      result(payment_mode: "cheque", reference_number: number, clean_name: number ? "#{label} #{number}" : label)
    end

    def parse_cash(text)
      return unless text.match?(/\A(?:CASH\s+DEP|BY\s+CASH|CASH\s+DEPOSIT|CDM)/i)

      result(payment_mode: "cash", clean_name: "Cash deposit")
    end

    # Splits on the separator the bank used. Slash-delimited narrations (UPI/.../DR/...) and
    # star-delimited ones are recognised first; hyphen is the common default.
    def tokenize(text)
      separator = if text.count("/") >= 2
        "/"
      elsif text.include?("*")
        "*"
      else
        "-"
      end

      text.split(separator).map(&:strip).reject(&:blank?)
    end

    def pick_counterparty(tokens)
      name = tokens.drop(1).find { |token| counterparty_token?(token) }
      name && titleize(name)
    end

    def counterparty_token?(token)
      return false if token.length < 2
      return false unless token.match?(/[A-Za-z]/)
      return false if token == VPA_PLACEHOLDER
      return false if NOISE_TOKENS.include?(token.upcase.delete(".").strip)
      return false if token.match?(/\A(?:NEFT|IMPS|RTGS|NACH|ACH)\s+[CD]R?\z/i)
      return false if token.match?(IFSC_REGEX) || token.match?(REFERENCE_REGEX)
      return false if token.match?(/\A[A-Z]{4}\z/) # bare bank code such as YESB / HDFC
      return false if token.match?(CARD_MASK_REGEX)

      true
    end

    def pick_reference(tokens)
      tokens.find { |t| t.match?(/\A\d{9,18}\z/) } ||
        tokens.find { |t| t.match?(REFERENCE_REGEX) && !t.match?(IFSC_REGEX) && t != VPA_PLACEHOLDER }
    end

    def titleize(name)
      name.squeeze(" ").split(" ").map do |word|
        ACRONYMS.include?(word.upcase) ? word.upcase : word.capitalize
      end.join(" ")
    end

    def result(attrs)
      EMPTY.merge(attrs)
    end
end
