# The dashboard's "Goals health" card: how many goals are on track, at risk or off track, and which one
# needs attention first. Uses each goal's latest daily snapshot; a goal that hasn't been checked yet
# (created today) falls back to a live projection.
class Goal::Health
  Entry = Data.define(:goal, :status, :shortfall, :progress_pct)

  attr_reader :family

  def initialize(family)
    @family = family
  end

  def any?
    entries.any?
  end

  def counts
    GoalSnapshot::STATUSES.keys.index_with { |status| entries.count { |entry| entry.status == status } }
  end

  # The most unhealthy goal, ties broken by the biggest shortfall. Nil when every goal is on track.
  def worst
    worst = entries.max_by { |entry| [ GoalSnapshot::SEVERITY.fetch(entry.status), entry.shortfall ] }
    worst unless worst&.status == "on_track"
  end

  def entries
    @entries ||= begin
      goals = family.goals.ordered.to_a
      latest = GoalSnapshot.where(goal_id: goals.map(&:id)).select("DISTINCT ON (goal_id) goal_snapshots.*").order(:goal_id, date: :desc).index_by(&:goal_id)

      goals.map do |goal|
        if (snapshot = latest[goal.id])
          Entry.new(goal: goal, status: snapshot.status, shortfall: snapshot.shortfall, progress_pct: snapshot.progress_pct)
        else
          projection = goal.projection
          Entry.new(goal: goal, status: projection.status, shortfall: projection.shortfall, progress_pct: projection.progress_pct)
        end
      end
    end
  end
end
