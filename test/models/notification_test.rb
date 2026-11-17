require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
  end

  def notify(**overrides)
    Notification.notify(**{ user: @user, kind: "premium_due", title: "Premium due", dedupe_key: "premium_due:1" }.merge(overrides))
  end

  test "creates a notification for the user and their family" do
    notification = notify(body: "Soon", url: "/insurance_policies")

    assert notification.persisted?
    assert_equal @user.family, notification.family
    assert_not notification.read?
  end

  test "does not repeat a notification with the same dedupe key" do
    assert notify
    assert_no_difference "Notification.count" do
      assert_nil notify
    end
  end

  test "the same dedupe key is fine for another user and a different key is fine for the same user" do
    notify

    assert_difference "Notification.count", 2 do
      notify(user: users(:family_member))
      notify(dedupe_key: "premium_due:2")
    end
  end

  test "the database enforces the dedupe key per user" do
    notify

    assert_raises(ActiveRecord::RecordNotUnique) do
      Notification.new(user: @user, family: @user.family, kind: "premium_due", title: "x", dedupe_key: "premium_due:1").save!(validate: false)
    end
  end

  test "notifications without a dedupe key are never deduplicated" do
    assert_difference "Notification.count", 2 do
      notify(dedupe_key: nil)
      notify(dedupe_key: nil)
    end
  end

  test "skips a kind the user turned off" do
    NotificationPreference.create!(user: @user, disabled_kinds: [ "premium_due" ])

    assert_no_difference "Notification.count" do
      assert_nil notify
    end
    assert notify(kind: "stale_navs", dedupe_key: "stale_navs:1")
  end

  test "the monthly summary has its own switch" do
    NotificationPreference.create!(user: @user, monthly_summary: false)

    assert_nil notify(kind: "goal_summary", dedupe_key: "goal_summary:2026-12")
  end

  test "marks as read once" do
    notification = notify
    notification.mark_read!
    first_read_at = notification.read_at
    notification.mark_read!

    assert notification.read?
    assert_equal first_read_at, notification.reload.read_at
  end

  test "email delivery needs SMTP settings" do
    with_env_overrides SMTP_ADDRESS: nil do
      assert_not Notification.email_delivery_configured?
    end
    with_env_overrides SMTP_ADDRESS: "smtp.example.com" do
      assert Notification.email_delivery_configured?
    end
  end

  test "email is off by default and needs both the opt-in and SMTP" do
    preferences = NotificationPreference.for(@user)
    assert_not preferences.email_enabled?
    assert_not preferences.include_amounts?

    preferences.email_enabled = true
    with_env_overrides SMTP_ADDRESS: nil do
      assert_not preferences.email_deliverable?
    end
    with_env_overrides SMTP_ADDRESS: "smtp.example.com" do
      assert preferences.email_deliverable?
    end
  end

  test "an email is sent once to an opted-in user when SMTP is configured" do
    preferences = NotificationPreference.create!(user: @user, email_enabled: true)
    notify

    with_env_overrides SMTP_ADDRESS: "smtp.example.com" do
      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        assert_equal 1, Notification.deliver_digest(preferences)
      end
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        assert_equal 0, Notification.deliver_digest(preferences)
      end
    end
  end

  test "no email without SMTP or without the opt-in" do
    notify

    with_env_overrides SMTP_ADDRESS: nil do
      assert_equal 0, Notification.deliver_digest(NotificationPreference.create!(user: @user, email_enabled: true))
    end

    with_env_overrides SMTP_ADDRESS: "smtp.example.com" do
      assert_equal 0, Notification.deliver_digest(NotificationPreference.for(users(:family_member)))
    end
  end

  test "the email job emails only opted-in users" do
    notify
    notify(user: users(:family_member), dedupe_key: "premium_due:1")
    NotificationPreference.create!(user: @user, email_enabled: true)

    with_env_overrides SMTP_ADDRESS: "smtp.example.com" do
      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        SendNotificationDigestsJob.perform_now
      end
    end
    assert_equal [ @user.email ], ActionMailer::Base.deliveries.last.to
  end

  test "the email job does nothing without SMTP" do
    notify
    NotificationPreference.create!(user: @user, email_enabled: true)

    with_env_overrides SMTP_ADDRESS: nil do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        SendNotificationDigestsJob.perform_now
      end
    end
  end
end
