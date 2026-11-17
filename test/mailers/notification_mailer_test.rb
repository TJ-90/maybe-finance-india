require "test_helper"

class NotificationMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:family_admin)
    @notification = Notification.notify(
      user: @user, kind: "goal_status", title: "Home down payment is at risk",
      body: "Status changed from on track to at risk.", detail: "Shortfall ₹1.2L", url: "/goals/1", dedupe_key: "x"
    )
  end

  test "leaves amounts out by default" do
    email = NotificationMailer.with(user: @user, notifications: [ @notification ]).digest

    assert_equal [ @user.email ], email.to
    [ email.html_part.body.to_s, email.text_part.body.to_s ].each do |body|
      assert_includes body, "Home down payment is at risk"
      assert_includes body, "Status changed from on track to at risk."
      assert_not_includes body, "Shortfall"
      assert_not_includes body, "₹"
    end
  end

  test "includes amounts when the user turned them on" do
    NotificationPreference.create!(user: @user, include_amounts: true)
    email = NotificationMailer.with(user: @user, notifications: [ @notification ]).digest

    assert_includes email.html_part.body.to_s, "Shortfall ₹1.2L"
    assert_includes email.text_part.body.to_s, "Shortfall ₹1.2L"
  end

  test "links to the app with absolute urls" do
    email = NotificationMailer.with(user: @user, notifications: [ @notification ]).digest

    assert_match %r{https?://\S+/goals/1}, email.text_part.body.to_s
    assert_match %r{https?://\S+/notifications}, email.text_part.body.to_s
  end
end
