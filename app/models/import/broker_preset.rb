# A broker tradebook (or mutual fund transaction template) layout from config/india_broker_presets.yml.
# Given the headers of an uploaded CSV it works out which header plays which role, and turns each
# CSV line into the attributes of an import row. It never saves anything.
class Import::BrokerPreset
  CONFIG_PATH = Rails.root.join("config", "india_broker_presets.yml")
  # A time of day after the date ("2024-01-15T09:32:11", "15-01-2024 09:32", "15-01-2024 9:32 PM")
  TIME_SUFFIX = /[T\s]+\d{1,2}:\d{2}(:\d{2}(\.\d+)?)?\s*([ap]m)?\s*(Z|[+-]\d{2}:?\d{2})?\z/i

  attr_reader :key, :label, :kind, :confidence, :date_format

  class << self
    def all
      presets.values
    end

    def find(key)
      presets[key.to_s]
    end

    def options
      all.map { |preset| [ preset.label, preset.key ] }
    end

    # The first preset whose required columns are all present in the headers
    def detect(headers)
      all.find { |preset| preset.matches?(headers) }
    end

    private
      def presets
        @presets ||= begin
          raw = YAML.safe_load_file(CONFIG_PATH, symbolize_names: false) || {}
          raw.fetch("presets", {}).to_h { |key, config| [ key, new(key, config) ] }
        end
      end
  end

  def initialize(key, config)
    @key = key
    @config = config
    @label = config.fetch("label")
    @kind = config.fetch("kind")
    @confidence = config.fetch("confidence", "unverified")
    @date_format = config.fetch("date_format")
  end

  def unverified?
    confidence != "confirmed"
  end

  def mutual_fund?
    @config["default_mic"] == Security::AMFI_MIC
  end

  def currency
    @config.fetch("currency", "INR")
  end

  # CSV text offered as a sample download
  def template
    @config.fetch("template")
  end

  def matches?(headers)
    columns = resolve_columns(headers)
    @config.fetch("required", []).all? { |role| columns[role].present? }
  end

  # role => the header found in the file (nil when absent)
  def resolve_columns(headers)
    by_normalized = headers.compact.index_by { |header| normalize(header) }

    @config.fetch("columns", {}).transform_values do |candidates|
      candidates.lazy.filter_map { |candidate| by_normalized[normalize(candidate)] }.first
    end
  end

  # Attributes of an Import::Row for one CSV line, or nil when the line is not a trade this preset
  # imports (for example futures and options lines in a Zerodha tradebook).
  def row_attributes(csv_row, columns)
    return nil unless accepted?(csv_row, columns)

    trade_type = cell(csv_row, columns, "type")
    direction = direction_of(trade_type)
    quantity = number(cell(csv_row, columns, "quantity")).abs
    price = number(cell(csv_row, columns, "price"))
    amount = number(cell(csv_row, columns, "amount")).abs
    scheme_or_symbol = cell(csv_row, columns, mutual_fund? ? "scheme" : "symbol")
    isin = cell(csv_row, columns, "isin").upcase.presence
    isin ||= scheme_or_symbol.upcase if scheme_or_symbol.upcase.match?(Import::InvestmentRowLookup::ISIN_PATTERN)

    signed_quantity = direction ? (quantity * direction) : nil
    price = (amount / quantity).round(4) if price.zero? && amount.positive? && quantity.positive?

    {
      date: date_text(cell(csv_row, columns, "date")),
      ticker: scheme_or_symbol,
      isin: isin,
      exchange_operating_mic: mic_for(cell(csv_row, columns, "exchange")),
      qty: signed_quantity ? signed_quantity.to_s("F") : "",
      price: price.to_s("F"),
      amount: amount.positive? && direction ? (amount * direction).to_s("F") : "",
      currency: currency,
      name: row_name(direction, scheme_or_symbol),
      entity_type: trade_type,
      folio_number: cell(csv_row, columns, "folio"),
      external_id: cell(csv_row, columns, "trade_id"),
      account: "",
      category: "",
      tags: "",
      notes: ""
    }
  end

  private
    # +1 for a buy, -1 for a sell, nil when the type is neither (the row then shows up as invalid)
    def direction_of(trade_type)
      value = normalize(trade_type)
      return 1 if @config.fetch("buy_values", []).map { |v| normalize(v) }.include?(value)
      return -1 if @config.fetch("sell_values", []).map { |v| normalize(v) }.include?(value)

      nil
    end

    def accepted?(csv_row, columns)
      @config.fetch("only", {}).all? do |role, allowed|
        column = columns[role]
        next true if column.nil?

        allowed.map(&:to_s).map(&:downcase).include?(csv_row[column].to_s.strip.downcase)
      end
    end

    def mic_for(exchange)
      @config.fetch("exchange_mics", {})[exchange.to_s.strip.upcase] || @config["default_mic"]
    end

    def row_name(direction, label)
      verb = direction == -1 ? "Sell" : "Buy"
      "#{verb} #{label}".strip
    end

    # Dates keep the text of the file ("10 Jan 2025" stays whole); only a time part is dropped
    def date_text(value)
      value.to_s.strip.sub(TIME_SUFFIX, "")
    end

    def number(value)
      cleaned = value.to_s.gsub(/[^\d.\-]/, "")
      cleaned.match?(/\A-?\d+(\.\d+)?\z/) ? BigDecimal(cleaned) : BigDecimal("0")
    end

    def cell(csv_row, columns, role)
      column = columns[role]
      column ? csv_row[column].to_s.strip : ""
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end
end
