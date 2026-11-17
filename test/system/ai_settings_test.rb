require "application_system_test_case"

class AiSettingsTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    login_as(@user)
  end

  test "connect OpenRouter, key is masked afterwards, switching provider shows its fields" do
    visit settings_ai_provider_path

    assert_text "AI provider"
    assert_no_selector "input[name='ai_provider_setting[base_url]']", visible: true

    find("label", text: "OpenAI-compatible").click
    assert_selector "input[name='ai_provider_setting[base_url]']", visible: true

    find("label", text: "OpenRouter").click
    assert_no_selector "input[name='ai_provider_setting[base_url]']", visible: true
    assert_selector "input[name='ai_provider_setting[chat_model]'][placeholder='openai/gpt-4.1']"

    fill_in "API key", with: "sk-or-system-test-4321"
    click_button "Save"

    assert_text "AI settings saved"
    assert_text "Saved key ending in"
    assert_text "4321"
    assert_no_text "sk-or-system-test-4321"
    assert_equal "openrouter", @user.family.reload.ai_provider_setting.provider
  end
end
