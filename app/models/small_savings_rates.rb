# Effective-dated interest rates for Indian small-savings schemes and the EPF.
# Data lives in config/india_small_savings_rates.yml (verify it each quarter).
class SmallSavingsRates
  CONFIG_PATH = Rails.root.join("config", "india_small_savings_rates.yml")

  class << self
    # Rate in % p.a. for the scheme (e.g. :ppf) on the given date, or nil when the scheme is unknown
    # or the date precedes the first entry.
    def rate_on(scheme, date)
      rows = table[scheme.to_s]
      return nil if rows.blank?

      rows.select { |row| row[:effective_from] <= date }.max_by { |row| row[:effective_from] }&.fetch(:rate)
    end

    def schemes
      table.keys
    end

    private
      def table
        @table ||= load_table
      end

      def load_table
        raw = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [ Date ])

        raw.transform_values do |rows|
          rows.map do |row|
            { effective_from: row.fetch("effective_from").to_date, rate: row.fetch("rate").to_d }
          end
        end
      end
  end
end
