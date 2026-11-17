require "test_helper"

class Settings::NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "shows the defaults: email off, amounts off, 35 days" do
    get settings_notifications_path

    assert_response :success
    assert_select "input#notification_preference_email_enabled[checked]", count: 0
    assert_select "input#notification_preference_include_amounts[checked]", count: 0
    assert_select "input#notification_preference_monthly_summary[checked]"
    assert_select "input[name='notification_preference[stale_data_days]'][value='35']"
    Notification::KINDS.except("goal_summary").each_key do |kind|
      assert_select "input#kind_#{kind}[checked]"
    end
  end

  test "says so and disables email when the server has no SMTP settings" do
    with_env_overrides SMTP_ADDRESS: nil do
      get settings_notifications_path
    end

    assert_select "#email-unavailable"
    assert_select "input#notification_preference_email_enabled[disabled]"
  end

  test "email can be switched on when SMTP is configured" do
    with_env_overrides SMTP_ADDRESS: "smtp.example.com" do
      get settings_notifications_path
    end

    assert_select "#email-unavailable", count: 0
    assert_select "input#notification_preference_email_enabled:not([disabled])"
  end

  test "saves the settings" do
    patch settings_notifications_path, params: {
      notification_preference: {
        email_enabled: "1", include_amounts: "1", monthly_summary: "0", stale_data_days: "20",
        enabled_kinds: [ "", "goal_status", "premium_due" ]
      }
    }

    assert_redirected_to settings_notifications_path
    preferences = NotificationPreference.find_by!(user: @user)
    assert preferences.email_enabled?
    assert preferences.include_amounts?
    assert_not preferences.monthly_summary?
    assert_equal 20, preferences.stale_data_days
    assert_equal %w[stale_account stale_navs tax_year_end].sort, preferences.disabled_kinds.sort
    assert preferences.kind_enabled?("goal_status")
    assert_not preferences.kind_enabled?("stale_navs")
  end

  test "rejects a nonsensical threshold" do
    patch settings_notifications_path, params: { notification_preference: { stale_data_days: "0" } }

    assert_response :unprocessable_entity
    assert_nil NotificationPreference.find_by(user: @user)
  end

  test "settings are per user" do
    patch settings_notifications_path, params: { notification_preference: { stale_data_days: "10", enabled_kinds: [ "" ] } }

    assert_equal 35, NotificationPreference.for(users(:family_member)).stale_data_days
    assert NotificationPreference.for(users(:family_member)).kind_enabled?("goal_status")
  end

  test "is linked from the settings nav" do
    get settings_preferences_path

    assert_select "a[href=?]", settings_notifications_path, minimum: 1
  end
end
