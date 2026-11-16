# A bank / credit-card export layout from config/india_statement_presets.yml. Given an
# uploaded CSV it works out which header plays which role and returns import attributes
# that pre-fill the configuration form. It never saves anything.
class Import::StatementPreset
  CONFIG_PATH = Rails.root.join("config", "india_statement_presets.yml")
  KIND_LABELS = { "savings" => "Bank accounts", "credit_card" => "Credit cards", "generic" => "Other" }.freeze

  attr_reader :key, :label, :kind, :confidence

  class << self
    def all
      presets.values
    end

    def find(key)
      presets[key.to_s]
    end

    # Grouped options for a <select>
    def grouped_options
      all.group_by(&:kind).map do |kind, presets|
        [ KIND_LABELS.fetch(kind, kind.humanize), presets.map { |preset| [ preset.label, preset.key ] } ]
      end
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
  end

  def unverified?
    confidence != "confirmed"
  end

  # Attributes to assign to the import. Only roles that matched a header are returned.
  def attributes_for(import)
    headers = import.csv_headers.compact
    columns = resolve_columns(headers)

    attrs = {
      date_format: @config["date_format"],
      number_format: @config["number_format"],
      date_col_label: columns["date"],
      name_col_label: columns["name"]
    }

    case @config["strategy"]
    when "debit_credit_columns"
      attrs.merge!(
        amount_type_strategy: "debit_credit_columns",
        debit_col_label: columns["debit"],
        credit_col_label: columns["credit"],
        amount_col_label: nil
      )
    when "custom_column"
      attrs.merge!(
        amount_type_strategy: "custom_column",
        amount_col_label: columns["amount"],
        entity_type_col_label: columns["type"],
        amount_type_inflow_value: inflow_value_in(import, columns["type"])
      )
    end

    attrs.compact_blank
  end

  private
    def resolve_columns(headers)
      by_normalized = headers.index_by { |header| normalize(header) }

      @config.fetch("columns", {}).transform_values do |candidates|
        candidates.lazy.filter_map { |candidate| by_normalized[normalize(candidate)] }.first
      end
    end

    def inflow_value_in(import, type_column)
      configured = @config["inflow_value"]
      return configured if type_column.blank?

      values = import.csv_rows.map { |row| row[type_column] }.compact.uniq
      values.find { |value| value.casecmp?(configured.to_s) } || configured
    end

    def normalize(header)
      header.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end
end
