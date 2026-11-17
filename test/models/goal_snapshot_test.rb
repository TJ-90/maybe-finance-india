require "test_helper"

class GoalSnapshotTest < ActiveSupport::TestCase
  setup do
    @goal = goals(:home)
    @today = Date.new(2026, 11, 16)
  end

  def status_for(projected:, target:)
    projection = Goal::Projection.new(@goal, today: @today, current_value: 0)
    projection.stubs(:projected_corpus).returns(projected)
    projection.stubs(:inflation_adjusted_target).returns(target)
    projection.status
  end

  test "status is on track when the projection reaches the target" do
    assert_equal "on_track", status_for(projected: 1000, target: 1000)
    assert_equal "on_track", status_for(projected: 1500, target: 1000)
  end

  test "status is at risk when the shortfall is at most 10% of the target" do
    assert_equal "at_risk", status_for(projected: 950, target: 1000)
    assert_equal "at_risk", status_for(projected: 900, target: 1000)
  end

  test "status is off track when the shortfall is more than 10% of the target" do
    assert_equal "off_track", status_for(projected: 899, target: 1000)
    assert_equal "off_track", status_for(projected: 0, target: 1000)
  end

  test "records one snapshot per goal and date, refreshing it when run again" do
    snapshot = nil
    assert_difference -> { @goal.goal_snapshots.count }, 1 do
      snapshot = @goal.record_snapshot!(date: @today)
      @goal.record_snapshot!(date: @today)
    end

    assert_in_delta @goal.projection(today: @today).projected_corpus, snapshot.projected_corpus.to_f, 0.01

    @goal.update!(monthly_sip: 1_000_000)
    refreshed = @goal.record_snapshot!(date: @today)

    assert_equal snapshot.id, refreshed.id
    assert_equal "on_track", refreshed.status
    assert_equal 1, @goal.goal_snapshots.where(date: @today).count
  end

  test "the database refuses a second snapshot for the same goal and date" do
    @goal.record_snapshot!(date: @today)

    assert_raises(ActiveRecord::RecordNotUnique) do
      GoalSnapshot.new(goal: @goal, date: @today, status: "on_track").save!(validate: false)
    end
  end

  test "finds the last status change and the snapshot before" do
    { 3 => "on_track", 2 => "on_track", 1 => "at_risk", 0 => "at_risk" }.each do |days_ago, status|
      @goal.goal_snapshots.create!(date: @today - days_ago, status: status)
    end

    after, before = @goal.last_status_change

    assert_equal @today - 1, after.date
    assert_equal "on_track", before.status
    assert after.worse_than?(before.status)
  end

  test "no status change when the status never moved" do
    @goal.goal_snapshots.create!(date: @today - 1, status: "on_track")
    @goal.goal_snapshots.create!(date: @today, status: "on_track")

    assert_nil @goal.last_status_change
  end
end
