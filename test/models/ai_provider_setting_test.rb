require "test_helper"

class AiProviderSettingTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "api key is encrypted at rest and never the raw column value" do
    setting = AiProviderSetting.create!(family: @family, provider: "openai", api_key: "sk-test-secret-abcd")

    raw = AiProviderSetting.connection.select_value("SELECT api_key FROM ai_provider_settings WHERE id = '#{setting.id}'")

    assert_not_equal "sk-test-secret-abcd", raw
    assert_not_includes raw, "secret"
    assert_equal "sk-test-secret-abcd", setting.reload.api_key
    assert_equal "abcd", setting.api_key_hint
  end

  test "openai and openrouter require a key, openai_compatible requires base url and models" do
    assert_not AiProviderSetting.new(family: @family, provider: "openai").valid?
    assert_not AiProviderSetting.new(family: @family, provider: "openrouter").valid?

    setting = AiProviderSetting.new(family: @family, provider: "openai_compatible")
    assert_not setting.valid?
    assert setting.errors[:base_url].any?
    assert setting.errors[:chat_model].any?
    assert setting.errors[:fast_model].any?

    setting.assign_attributes(base_url: "http://localhost:11434/v1", chat_model: "llama3.1", fast_model: "llama3.1")
    assert setting.valid?, setting.errors.full_messages.to_sentence
  end

  test "base url must be https, or http only for localhost" do
    build = ->(url) { AiProviderSetting.new(family: @family, provider: "openai_compatible", base_url: url, chat_model: "m", fast_model: "m") }

    assert build.call("https://api.groq.com/openai/v1").valid?
    assert build.call("http://localhost:1234/v1").valid?
    assert build.call("http://127.0.0.1:8000/v1").valid?
    assert_not build.call("http://example.com/v1").valid?
    assert_not build.call("ftp://example.com").valid?
    assert_not build.call("javascript:alert(1)").valid?
    assert_not build.call("https://user:pass@example.com/v1").valid?
    assert_not build.call("not a url").valid?
  end

  test "remove_key! clears the key and disables" do
    setting = AiProviderSetting.create!(family: @family, provider: "openai", api_key: "sk-test-1234")
    setting.remove_key!

    assert_nil setting.reload.api_key
    assert_not setting.enabled?
  end

  test "default models per provider" do
    openai = AiProviderSetting.new(provider: "openai", api_key: "k").to_llm_config
    router = AiProviderSetting.new(provider: "openrouter", api_key: "k").to_llm_config

    assert_equal [ "gpt-4.1", "gpt-4.1-mini" ], [ openai.chat_model, openai.fast_model ]
    assert_equal [ "openai/gpt-4.1", "openai/gpt-4.1-mini" ], [ router.chat_model, router.fast_model ]
    assert_equal :responses, openai.api_style
    assert_equal :chat_completions, router.api_style
  end

  test "openrouter attribution headers come from the product name" do
    config = AiProviderSetting.new(provider: "openrouter", api_key: "k").to_llm_config
    assert_equal Rails.application.config.x.product_name, config.extra_headers["X-Title"]

    off = AiProviderSetting.new(provider: "openrouter", api_key: "k", openrouter_attribution: false).to_llm_config
    assert_equal({}, off.extra_headers)
  end
end
