require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = families(:dylan_family)
    sign_in @user
  end

  test "gets index" do
    get chats_url
    assert_response :success
  end

  test "creates chat" do
    assert_difference("Chat.count") do
      post chats_url, params: { chat: { content: "Hello", ai_model: "gpt-4.1" } }
    end

    assert_redirected_to chat_path(Chat.order(created_at: :desc).first, thinking: true)
  end

  test "consent card links to Settings > AI when no provider is configured" do
    @user.update!(ai_enabled: false)
    Rails.application.config.app_mode.stubs(:self_hosted?).returns(true)
    Setting.stubs(:openai_access_token).returns(nil)

    with_env_overrides OPENAI_ACCESS_TOKEN: nil, OPENROUTER_API_KEY: nil, AI_BASE_URL: nil do
      get chats_url
      assert_select "a[href=?]", settings_ai_provider_path
      assert_not_includes response.body, "OPENAI_ACCESS_TOKEN"
    end
  end

  test "shows chat" do
    get chat_url(chats(:one))
    assert_response :success
  end

  test "destroys chat" do
    assert_difference("Chat.count", -1) do
      delete chat_url(chats(:one))
    end

    assert_redirected_to chats_url
  end

  test "should not allow access to other user's chats" do
    other_user = users(:family_member)
    other_chat = Chat.create!(user: other_user, title: "Other User's Chat")

    get chat_url(other_chat)
    assert_response :not_found

    delete chat_url(other_chat)
    assert_response :not_found
  end
end
