# A family's saved connection to an LLM provider for the AI assistant, auto-categorization and
# merchant detection. One per family. The API key is encrypted at rest and is never rendered back.
class AiProviderSetting < ApplicationRecord
  PROVIDERS = {
    "openai" => "OpenAI",
    "openrouter" => "OpenRouter",
    "openai_compatible" => "OpenAI-compatible"
  }.freeze

  # Example defaults. The user can change them. openai_compatible has none (required).
  DEFAULT_MODELS = {
    "openai" => { chat: "gpt-4.1", fast: "gpt-4.1-mini" },
    "openrouter" => { chat: "openai/gpt-4.1", fast: "openai/gpt-4.1-mini" },
    "openai_compatible" => { chat: nil, fast: nil }
  }.freeze

  BASE_URLS = {
    "openai" => "https://api.openai.com/v1",
    "openrouter" => "https://openrouter.ai/api/v1"
  }.freeze

  MODEL_SUGGESTIONS = {
    "openai" => %w[gpt-4.1 gpt-4.1-mini gpt-4o gpt-4o-mini],
    "openrouter" => %w[openai/gpt-4.1 openai/gpt-4.1-mini anthropic/claude-sonnet-4 google/gemini-2.5-flash],
    "openai_compatible" => %w[llama3.1 qwen2.5 mistral]
  }.freeze

  LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1 [::1]].freeze

  belongs_to :family

  encrypts :api_key

  attribute :provider, :string, default: "openai"

  normalizes :base_url, with: ->(url) { url.to_s.strip.chomp("/").presence }
  normalizes :chat_model, :fast_model, with: ->(model) { model.to_s.strip.presence }

  validates :provider, inclusion: { in: PROVIDERS.keys }
  validates :api_key, presence: true, if: :api_key_required?
  validates :base_url, presence: true, if: :openai_compatible?
  validates :chat_model, :fast_model, presence: true, if: :openai_compatible?
  validate :base_url_must_be_safe
  validates :last_test_status, inclusion: { in: %w[ok error] }, allow_nil: true

  PROVIDERS.each_key do |name|
    define_method(:"#{name}?") { provider == name }
  end

  def provider_label
    PROVIDERS[provider]
  end

  def api_key_required?
    enabled? && !openai_compatible?
  end

  def api_key?
    api_key.present?
  end

  # Only the last four characters are ever shown
  def api_key_hint
    return nil unless api_key?

    api_key.last(4)
  end

  def remove_key!
    update!(api_key: nil, enabled: false, last_test_status: nil, last_test_message: nil, last_tested_at: nil)
  end

  def record_test!(status, message)
    update_columns(last_test_status: status, last_test_message: message, last_tested_at: Time.current)
  end

  def usable?
    enabled? && valid? && (api_key? || openai_compatible?)
  end

  def to_llm_config(source: :family)
    defaults = DEFAULT_MODELS.fetch(provider)

    LlmConfig.new(
      provider: provider,
      api_key: api_key,
      base_url: base_url,
      chat_model: chat_model || defaults[:chat],
      fast_model: fast_model || defaults[:fast],
      openrouter_attribution: openrouter_attribution?,
      source: source
    )
  end

  # Calls a cheap endpoint with the saved key and stores ok/error plus a timestamp. Returns [status, message].
  def test_connection!
    status, message = ConnectionTester.new(to_llm_config).call
    record_test!(status, message)
    [ status, message ]
  end

  def model_suggestions
    MODEL_SUGGESTIONS[provider]
  end

  private
    def base_url_must_be_safe
      return if base_url.blank?

      uri = URI.parse(base_url)
      host = uri.host.to_s

      if uri.scheme == "https"
        errors.add(:base_url, "must include a host") if host.blank?
      elsif uri.scheme == "http"
        errors.add(:base_url, "can only use http for localhost. Use https for anything else") unless LOCAL_HOSTS.include?(host)
      else
        errors.add(:base_url, "must start with https://")
      end

      errors.add(:base_url, "must not contain a username or password") if uri.userinfo.present?
    rescue URI::InvalidURIError
      errors.add(:base_url, "is not a valid URL")
    end
end
