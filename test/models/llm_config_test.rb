require "test_helper"

class LlmConfigTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "nothing configured resolves to nil" do
    with_env_overrides OPENAI_ACCESS_TOKEN: nil, OPENROUTER_API_KEY: nil, AI_BASE_URL: nil do
      Setting.stubs(:openai_access_token).returns(nil)
      assert_nil LlmConfig.resolve(@family)
    end
  end

  test "saved enabled family setting wins over env" do
    AiProviderSetting.create!(family: @family, provider: "openrouter", api_key: "or-key-1234")

    with_env_overrides OPENAI_ACCESS_TOKEN: "sk-env" do
      config = LlmConfig.resolve(@family)
      assert_equal "openrouter", config.provider
      assert_equal "or-key-1234", config.api_key
      assert_equal :family, config.source
    end
  end

  test "disabled family setting falls back to env" do
    AiProviderSetting.create!(family: @family, provider: "openrouter", api_key: "or-key-1234", enabled: false)

    with_env_overrides OPENAI_ACCESS_TOKEN: "sk-env" do
      config = LlmConfig.resolve(@family)
      assert_equal "openai", config.provider
      assert_equal "sk-env", config.api_key
      assert_equal :env, config.source
    end
  end

  test "env fallbacks in order: openai token, openrouter key, ai base url" do
    Setting.stubs(:openai_access_token).returns(nil)

    with_env_overrides OPENAI_ACCESS_TOKEN: nil, OPENROUTER_API_KEY: "or-env", AI_BASE_URL: "http://localhost:11434/v1", AI_CHAT_MODEL: nil, AI_FAST_MODEL: nil do
      config = LlmConfig.resolve(@family)
      assert_equal "openrouter", config.provider
      assert_equal "openai/gpt-4.1", config.chat_model
    end

    with_env_overrides OPENAI_ACCESS_TOKEN: nil, OPENROUTER_API_KEY: nil, AI_BASE_URL: "http://localhost:11434/v1", AI_CHAT_MODEL: "llama3.1", AI_FAST_MODEL: nil do
      config = LlmConfig.resolve(@family)
      assert_equal "openai_compatible", config.provider
      assert_equal "llama3.1", config.chat_model
      assert_equal "llama3.1", config.fast_model
      assert_equal "http://localhost:11434/v1", config.uri_base
    end
  end

  test "ai_base_url without a model is not usable" do
    Setting.stubs(:openai_access_token).returns(nil)

    with_env_overrides OPENAI_ACCESS_TOKEN: nil, OPENROUTER_API_KEY: nil, AI_BASE_URL: "http://localhost:11434/v1", AI_CHAT_MODEL: nil do
      assert_nil LlmConfig.resolve(@family)
    end
  end

  test "ai_available? uses a saved family key in self-hosted mode" do
    user = users(:family_admin)
    Setting.stubs(:openai_access_token).returns(nil)

    Rails.application.config.app_mode.stubs(:self_hosted?).returns(true)

    with_env_overrides OPENAI_ACCESS_TOKEN: nil, OPENROUTER_API_KEY: nil, AI_BASE_URL: nil do
      assert_not user.ai_available?

      AiProviderSetting.create!(family: user.family, provider: "openai", api_key: "sk-test-1234")
      assert user.reload.ai_available?
    end
  end

  test "registry builds the provider for the family's API style" do
    AiProviderSetting.create!(family: @family, provider: "openrouter", api_key: "or-key-1234")
    assert_kind_of Provider::OpenaiCompatible, Provider::Registry.llm_provider(@family)

    @family.ai_provider_setting.update!(provider: "openai", api_key: "sk-test-1234")
    assert_kind_of Provider::Openai, Provider::Registry.llm_provider(@family.reload)
  end
end
