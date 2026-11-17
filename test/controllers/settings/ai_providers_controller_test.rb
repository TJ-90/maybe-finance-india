require "test_helper"

class Settings::AiProvidersControllerTest < ActionDispatch::IntegrationTest
  KEY = "sk-test-supersecret-wxyz"

  setup do
    @admin = users(:family_admin)
    @family = @admin.family
  end

  test "members cannot view or edit" do
    sign_in users(:family_member)

    get settings_ai_provider_url
    assert_redirected_to settings_profile_url

    patch settings_ai_provider_url, params: { ai_provider_setting: { provider: "openai", api_key: KEY } }
    assert_redirected_to settings_profile_url
    assert_nil @family.reload.ai_provider_setting
  end

  test "admin sees the page" do
    sign_in @admin
    get settings_ai_provider_url

    assert_response :success
    assert_select "input[type=radio][name='ai_provider_setting[provider]']", 3
    assert_match "platform.openai.com", response.body
    assert_match "don't include API access", response.body
  end

  test "saves a provider and never renders the key back" do
    sign_in @admin

    patch settings_ai_provider_url, params: { ai_provider_setting: { provider: "openrouter", api_key: KEY, chat_model: "openai/gpt-4.1", enabled: "1" } }
    assert_redirected_to settings_ai_provider_url

    setting = @family.reload.ai_provider_setting
    assert_equal "openrouter", setting.provider
    assert_equal KEY, setting.api_key

    get settings_ai_provider_url
    assert_response :success
    assert_not_includes response.body, KEY
    assert_match "Saved key ending in", response.body
    assert_match "wxyz", response.body
    assert_select "input[name='ai_provider_setting[api_key]'][value]", 0
  end

  test "invalid save re-renders without echoing the key" do
    sign_in @admin

    patch settings_ai_provider_url, params: { ai_provider_setting: { provider: "openai_compatible", api_key: KEY, base_url: "http://example.com/v1", chat_model: "m", fast_model: "m" } }

    assert_response :unprocessable_entity
    assert_not_includes response.body, KEY
    assert_nil @family.reload.ai_provider_setting
  end

  test "blank key keeps the saved key, a new key replaces it" do
    AiProviderSetting.create!(family: @family, provider: "openai", api_key: KEY)
    sign_in @admin

    patch settings_ai_provider_url, params: { ai_provider_setting: { provider: "openai", api_key: "", chat_model: "gpt-4.1" } }
    assert_equal KEY, @family.reload.ai_provider_setting.api_key

    patch settings_ai_provider_url, params: { ai_provider_setting: { provider: "openai", api_key: "sk-new-key-1111" } }
    assert_equal "sk-new-key-1111", @family.reload.ai_provider_setting.api_key
  end

  test "switching provider without a new key drops the old key and is rejected" do
    AiProviderSetting.create!(family: @family, provider: "openai", api_key: KEY)
    sign_in @admin

    patch settings_ai_provider_url, params: { ai_provider_setting: { provider: "openrouter", api_key: "" } }

    assert_response :unprocessable_entity
    assert_equal KEY, @family.reload.ai_provider_setting.api_key
    assert_equal "openai", @family.ai_provider_setting.provider
  end

  test "remove key" do
    AiProviderSetting.create!(family: @family, provider: "openai", api_key: KEY)
    sign_in @admin

    delete remove_key_settings_ai_provider_url

    assert_redirected_to settings_ai_provider_url
    setting = @family.reload.ai_provider_setting
    assert_nil setting.api_key
    assert_not setting.enabled?
  end

  test "test connection success is saved" do
    AiProviderSetting.create!(family: @family, provider: "openai", api_key: KEY)
    stub_request(:get, "https://api.openai.com/v1/models")
      .with(headers: { "Authorization" => "Bearer #{KEY}" })
      .to_return(status: 200, body: { data: [ { id: "gpt-4.1" } ] }.to_json, headers: { "Content-Type" => "application/json" })
    sign_in @admin

    post test_connection_settings_ai_provider_url

    assert_redirected_to settings_ai_provider_url
    assert_match "Connected to api.openai.com", flash[:notice]
    setting = @family.reload.ai_provider_setting
    assert_equal "ok", setting.last_test_status
    assert setting.last_tested_at.present?
  end

  test "test connection failure maps the error and never shows the key" do
    AiProviderSetting.create!(family: @family, provider: "openai", api_key: KEY)
    stub_request(:get, "https://api.openai.com/v1/models")
      .to_return(status: 401, body: { error: { message: "Incorrect API key provided: #{KEY}" } }.to_json, headers: { "Content-Type" => "application/json" })
    sign_in @admin

    post test_connection_settings_ai_provider_url

    assert_equal "Invalid API key", flash[:alert]
    assert_equal "error", @family.reload.ai_provider_setting.last_test_status

    follow_redirect!
    assert_not_includes response.body, KEY
    assert_match "Invalid API key", response.body
  end

  test "test connection falls back to a 1-token completion when /models is missing" do
    AiProviderSetting.create!(family: @family, provider: "openai_compatible", base_url: "http://localhost:11434/v1", chat_model: "llama3.1", fast_model: "llama3.1")
    stub_request(:get, "http://localhost:11434/v1/models").to_return(status: 404, body: "not found")
    completion = stub_request(:post, "http://localhost:11434/v1/chat/completions")
      .with { |req| JSON.parse(req.body)["max_tokens"] == 1 }
      .to_return(status: 200, body: { choices: [ { message: { content: "H" } } ] }.to_json, headers: { "Content-Type" => "application/json" })
    sign_in @admin

    post test_connection_settings_ai_provider_url

    assert_requested completion
    assert_match "responded", flash[:notice]
  end

  test "test connection reports unreachable host" do
    AiProviderSetting.create!(family: @family, provider: "openai_compatible", base_url: "https://llm.example.com/v1", chat_model: "m", fast_model: "m", api_key: KEY)
    stub_request(:get, "https://llm.example.com/v1/models").to_timeout
    sign_in @admin

    post test_connection_settings_ai_provider_url

    assert_equal "Could not reach llm.example.com", flash[:alert]
  end

  test "test connection without a saved key asks to save first" do
    sign_in @admin
    post test_connection_settings_ai_provider_url
    assert_match "Save an API key first", flash[:alert]
  end
end
