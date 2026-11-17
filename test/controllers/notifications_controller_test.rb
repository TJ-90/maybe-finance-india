require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @notification = Notification.notify(user: @user, kind: "premium_due", title: "Term premium is due", body: "Due soon", url: "/insurance_policies", dedupe_key: "a")
    @other = Notification.notify(user: users(:family_member), kind: "premium_due", title: "Someone else's reminder", dedupe_key: "b")
  end

  test "inbox lists only my notifications" do
    get notifications_path

    assert_response :success
    assert_select "##{dom_id(@notification)}", text: /Term premium is due/
    assert_select "##{dom_id(@other)}", count: 0
    assert_select "button", text: /Mark all as read/
  end

  test "inbox shows an empty state" do
    @notification.destroy!
    get notifications_path

    assert_response :success
    assert_match(/No notifications yet/, response.body)
  end

  test "marks one notification as read" do
    patch notification_path(@notification)

    assert_redirected_to notifications_path
    assert @notification.reload.read?
  end

  test "cannot touch another user's notification" do
    patch notification_path(@other)

    assert_response :not_found
    assert_not @other.reload.read?
  end

  test "opening marks as read and goes to the page" do
    get open_notification_path(@notification)

    assert_redirected_to "/insurance_policies"
    assert @notification.reload.read?
  end

  test "opening never redirects off site" do
    @notification.update!(url: "https://evil.example.com/")
    get open_notification_path(@notification)

    assert_redirected_to notifications_path

    @notification.update!(url: "//evil.example.com/")
    get open_notification_path(@notification)

    assert_redirected_to notifications_path
  end

  test "marks all as read for me only" do
    post mark_all_read_notifications_path

    assert_redirected_to notifications_path
    assert @notification.reload.read?
    assert_not @other.reload.read?
  end

  test "the bell with the unread count is in the top bar and the nav keeps its items" do
    get root_path

    assert_response :success
    assert_select "a[data-testid=notification-bell][href=?]", notifications_path, minimum: 1
    assert_select "a[data-testid=notification-bell] span", text: "1", minimum: 1

    @notification.mark_read!
    get root_path

    assert_select "a[data-testid=notification-bell] span", count: 0
  end
end
