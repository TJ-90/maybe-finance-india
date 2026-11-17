require "test_helper"

class Notification::GoalAlertsTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @users = @family.users.to_a
    @goal = goals(:home)
    @today = Date.new(2026, 11, 16)
    goals(:emergency).destroy! # keep one goal so the assertions stay readable
  end

  def run_alerts(status, date: @today)
    Goal::Projection.any_instance.stubs(:status).returns(status)
    Notification::GoalAlerts.new(@family, today: date).run!
  end

  test "writes a snapshot for every goal" do
    assert_difference "GoalSnapshot.count", 1 do
      run_alerts("on_track")
    end
  end

  test "stays quiet on the first snapshot and when the status does not change" do
    assert_no_difference "Notification.count" do
      run_alerts("at_risk", date: @today - 1)
      run_alerts("at_risk")
    end
  end

  test "a goal that belongs to a member names the member" do
    member = @family.household_members.create!(name: "Rahul", relationship: "self", residency_status: "nri")
    @goal.update!(household_member: member)
    run_alerts("on_track", date: @today - 1)

    run_alerts("off_track")

    assert_equal "Rahul's #{@goal.name} is off track", @users.first.notifications.find_by!(kind: "goal_status").title
  end

  test "tells every family user when a goal slips" do
    run_alerts("on_track", date: @today - 1)

    assert_difference "Notification.where(kind: 'goal_status').count", @users.size do
      run_alerts("off_track")
    end

    notification = @users.first.notifications.find_by!(kind: "goal_status")
    assert_equal "#{@goal.name} is off track", notification.title
    assert_equal "/goals/#{@goal.id}", notification.url
    assert_match(/on track to off track/, notification.body)
    assert_no_match(/₹|\$/, notification.body)
    assert_match(/Shortfall/, notification.detail)
  end

  test "running again the same day does not repeat the alert" do
    run_alerts("on_track", date: @today - 1)
    run_alerts("at_risk")

    assert_no_difference "Notification.count" do
      run_alerts("at_risk")
    end
  end

  test "tells users when a goal recovers" do
    run_alerts("off_track", date: @today - 1)
    run_alerts("on_track")

    assert_equal "#{@goal.name} is back on track", @users.first.notifications.find_by!(kind: "goal_status").title
  end

  test "a partial improvement is reported as such" do
    run_alerts("off_track", date: @today - 1)
    run_alerts("at_risk")

    assert_equal "#{@goal.name} improved to at risk", @users.first.notifications.find_by!(kind: "goal_status").title
  end

  test "respects a user who turned goal alerts off" do
    NotificationPreference.create!(user: users(:family_member), disabled_kinds: [ "goal_status" ])
    run_alerts("on_track", date: @today - 1)
    run_alerts("at_risk")

    assert_equal 1, Notification.where(kind: "goal_status").count
    assert_equal 0, users(:family_member).notifications.count
  end

  test "sends the monthly summary on the 1st only, once" do
    first = Date.new(2026, 12, 1)

    assert_no_difference "Notification.where(kind: 'goal_summary').count" do
      run_alerts("on_track", date: first + 1)
    end

    assert_difference "Notification.where(kind: 'goal_summary').count", @users.size do
      run_alerts("at_risk", date: first)
      run_alerts("at_risk", date: first)
    end

    summary = @users.first.notifications.find_by!(kind: "goal_summary")
    assert_equal "1 goal: 1 at risk. #{@goal.name} needs the most attention.", summary.body
    assert_equal "goal_summary:2026-12", summary.dedupe_key
  end

  test "the monthly summary can be turned off" do
    NotificationPreference.create!(user: users(:family_admin), monthly_summary: false)
    run_alerts("on_track", date: Date.new(2026, 12, 1))

    assert_equal 0, users(:family_admin).notifications.where(kind: "goal_summary").count
    assert_equal 1, users(:family_member).notifications.where(kind: "goal_summary").count
  end

  test "the monitor job covers every family with goals" do
    assert_difference "GoalSnapshot.count", 1 do
      MonitorGoalsJob.perform_now(date: @today)
    end
  end
end
