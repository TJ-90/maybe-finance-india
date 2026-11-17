# The resolved connection details for the LLM provider a family uses. Resolution order:
#   1. the family's saved, enabled AiProviderSetting
#   2. instance-level fallbacks from ENV / Setting: OPENAI_ACCESS_TOKEN (OpenAI), then
#      OPENROUTER_API_KEY (OpenRouter), then AI_BASE_URL (OpenAI-compatible)
# `Provider::Registry.llm_provider(family)` is the only place that turns this into a provider object.
class LlmConfig
  attr_reader :provider, :api_key, :base_url, :chat_model, :fast_model, :openrouter_attribution, :source

  class << self
    def resolve(family)
      from_family(family) || from_env
    end

    def from_family(family)
      setting = family&.ai_provider_setting
      return nil unless setting&.usable?

      setting.to_llm_config(source: :family)
    end

    def from_env
      openai_token = ENV["OPENAI_ACCESS_TOKEN"].presence || Setting.openai_access_token.presence
      openrouter_key = ENV["OPENROUTER_API_KEY"].presence
      ai_base_url = ENV["AI_BASE_URL"].presence

      if openai_token
        build_env("openai", openai_token, nil)
      elsif openrouter_key
        build_env("openrouter", openrouter_key, nil)
      elsif ai_base_url
        build_env("openai_compatible", ENV["AI_API_KEY"].presence, ai_base_url)
      end
    end

    private
      def build_env(provider, key, base_url)
        defaults = AiProviderSetting::DEFAULT_MODELS.fetch(provider)
        chat_model = ENV["AI_CHAT_MODEL"].presence || defaults[:chat]
        fast_model = ENV["AI_FAST_MODEL"].presence || defaults[:fast] || chat_model
        return nil if chat_model.blank?

        new(provider: provider, api_key: key, base_url: base_url, chat_model: chat_model, fast_model: fast_model,
            openrouter_attribution: true, source: :env)
      end
  end

  def initialize(provider:, api_key:, base_url:, chat_model:, fast_model:, openrouter_attribution: true, source: :family)
    @provider = provider
    @api_key = api_key
    @base_url = base_url
    @chat_model = chat_model
    @fast_model = fast_model
    @openrouter_attribution = openrouter_attribution
    @source = source
  end

  # OpenAI keeps the Responses API. OpenRouter and OpenAI-compatible servers use Chat Completions.
  def api_style
    provider == "openai" ? :responses : :chat_completions
  end

  def uri_base
    base_url.presence || AiProviderSetting::BASE_URLS[provider]
  end

  def host
    URI.parse(uri_base).host
  rescue URI::InvalidURIError
    uri_base
  end

  def extra_headers
    return {} unless provider == "openrouter" && openrouter_attribution

    headers = { "X-Title" => Rails.application.config.x.product_name.to_s }
    app_host = Rails.application.config.action_mailer.default_url_options&.dig(:host)
    headers["HTTP-Referer"] = "https://#{app_host}" if app_host.present? && app_host != "localhost"
    headers
  end

  def client
    ::OpenAI::Client.new(
      access_token: api_key.presence || "not-needed",
      uri_base: uri_base,
      extra_headers: extra_headers,
      request_timeout: 120
    )
  end
end
