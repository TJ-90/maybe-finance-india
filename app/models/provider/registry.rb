class Provider::Registry
  include ActiveModel::Validations

  Error = Class.new(StandardError)

  CONCEPTS = %i[exchange_rates securities llm]

  validates :concept, inclusion: { in: CONCEPTS }

  class << self
    def for_concept(concept)
      new(concept.to_sym)
    end

    def get_provider(name)
      send(name)
    rescue NoMethodError
      raise Error.new("Provider '#{name}' not found in registry")
    end

    # The LLM provider for a family: its saved AI settings first, then the instance ENV fallbacks (see LlmConfig).
    # This is the single place an LLM provider object is built. Returns nil when nothing is configured.
    def llm_provider(family = nil)
      config = LlmConfig.resolve(family)
      return nil if config.nil?

      case config.api_style
      when :responses
        Provider::Openai.new(config.api_key, chat_model: config.chat_model, fast_model: config.fast_model, config: config)
      else
        Provider::OpenaiCompatible.new(config)
      end
    end

    def plaid_provider_for_region(region)
      region.to_sym == :us ? plaid_us : plaid_eu
    end

    private
      def stripe
        secret_key = ENV["STRIPE_SECRET_KEY"]
        webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]

        return nil unless secret_key.present? && webhook_secret.present?

        Provider::Stripe.new(secret_key:, webhook_secret:)
      end

      # Free Indian market data sources (AMFI/MFAPI for mutual funds, Yahoo for NSE/BSE). On by default.
      # Set DISABLE_INDIAN_MARKET_DATA=true to turn them off. Synth, when configured, handles other exchanges.
      def indian_markets
        return nil if indian_market_data_disabled?

        Provider::IndianMarkets.new(fallback: synth)
      end

      def frankfurter
        return nil if indian_market_data_disabled?

        Provider::Frankfurter.new
      end

      def amfi
        return nil if indian_market_data_disabled?

        Provider::Amfi.new
      end

      def indian_market_data_disabled?
        ActiveModel::Type::Boolean.new.cast(ENV["DISABLE_INDIAN_MARKET_DATA"]) == true
      end

      def synth
        api_key = ENV.fetch("SYNTH_API_KEY", Setting.synth_api_key)

        return nil unless api_key.present?

        Provider::Synth.new(api_key)
      end

      def plaid_us
        config = Rails.application.config.plaid

        return nil unless config.present?

        Provider::Plaid.new(config, region: :us)
      end

      def plaid_eu
        config = Rails.application.config.plaid_eu

        return nil unless config.present?

        Provider::Plaid.new(config, region: :eu)
      end

      def github
        Provider::Github.new
      end

      # Instance-level LLM provider (no family): the ENV / Setting fallbacks only
      def openai
        llm_provider(nil)
      end
  end

  def initialize(concept)
    @concept = concept
    validate!
  end

  def providers
    available_providers.map { |p| self.class.send(p) }
  end

  # The first provider for this concept that is configured (e.g. Indian markets before Synth), or nil
  def first_provider
    available_providers.each do |name|
      provider = self.class.send(name)
      return provider if provider.present?
    end

    nil
  end

  def get_provider(name)
    provider_method = available_providers.find { |p| p == name.to_sym }

    raise Error.new("Provider '#{name}' not found for concept: #{concept}") unless provider_method.present?

    self.class.send(provider_method)
  end

  private
    attr_reader :concept

    def available_providers
      case concept
      when :exchange_rates
        %i[frankfurter synth]
      when :securities
        %i[indian_markets synth]
      when :llm
        %i[openai]
      else
        %i[synth plaid_us plaid_eu github openai]
      end
    end
end
