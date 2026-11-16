# Looks up a canonical merchant name and a suggested category name for an imported
# statement line, from config/india_merchant_categories.yml. It only suggests; callers decide
# whether a hint may be applied (blank, unlocked category only).
class Transaction::MerchantHint
  CONFIG_PATH = Rails.root.join("config", "india_merchant_categories.yml")

  Hint = Data.define(:merchant_name, :category_name)

  class << self
    # The parsed counterparty, VPA and clean name of a narration (nils are ignored)
    def match(counterparty: nil, vpa: nil, clean_name: nil)
      haystack = [ counterparty, vpa, clean_name ].compact.join(" ").downcase
      return if haystack.blank?

      merchant = merchants.find { |entry| entry[:regex].match?(haystack) }
      return Hint.new(merchant_name: merchant[:name], category_name: merchant[:category]) if merchant

      narration = narrations.find { |entry| entry[:clean_name] == clean_name.to_s.downcase }
      Hint.new(merchant_name: nil, category_name: narration[:category]) if narration
    end

    def reload!
      @config = nil
    end

    private
      def merchants
        config[:merchants]
      end

      def narrations
        config[:narrations]
      end

      def config
        @config ||= begin
          raw = YAML.safe_load_file(CONFIG_PATH, symbolize_names: true) || {}

          {
            merchants: Array(raw[:merchants]).map do |entry|
              phrases = Array(entry[:patterns]).map { |pattern| Regexp.escape(pattern.to_s.downcase) }
              entry.merge(regex: /(?<![a-z0-9])(?:#{phrases.join("|")})(?![a-z0-9])/)
            end,
            narrations: Array(raw[:narrations]).map { |entry| entry.merge(clean_name: entry[:clean_name].to_s.downcase) }
          }
        end
      end
  end
end
