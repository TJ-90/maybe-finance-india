# The daily goal check for one family: writes today's snapshot for every goal, tells the family's
# users when a goal's status changed since the previous snapshot, and on the 1st of the month sends
# the monthly summary. Running it again on the same day changes nothing.
class Notification::GoalAlerts
  attr_reader :family, :today

  def initialize(family, today: Date.current)
    @family = family
    @today = today
  end

  def run!
    snapshots = family.goals.ordered.includes(:household_member).map do |goal|
      previous = goal.goal_snapshots.where(date: ...today).order(date: :desc).first
      snapshot = goal.record_snapshot!(date: today)
      notify_status_change(goal, previous, snapshot) if previous && previous.status != snapshot.status
      snapshot
    end

    send_monthly_summary(snapshots) if today.day == 1 && snapshots.any?
    snapshots
  end

  private
    def users
      @users ||= family.users.where(active: true).to_a
    end

    def notify_status_change(goal, previous, snapshot)
      worse = snapshot.worse_than?(previous.status)
      name = goal_label(goal)
      title, body =
        if snapshot.status == "on_track"
          [ "#{name} is back on track", "Your projection now reaches the target again." ]
        elsif worse
          [ "#{name} is #{snapshot.status_label.downcase}", "Status changed from #{previous.status_label.downcase} to #{snapshot.status_label.downcase}. Review the monthly SIP or the money allocated to this goal." ]
        else
          [ "#{name} improved to #{snapshot.status_label.downcase}", "Status changed from #{previous.status_label.downcase} to #{snapshot.status_label.downcase}." ]
        end

      users.each do |user|
        Notification.notify(
          user: user, kind: "goal_status", title: title, body: body, detail: status_detail(goal, snapshot),
          url: url_helpers.goal_path(goal), dedupe_key: "goal_status:#{goal.id}:#{snapshot.date.iso8601}"
        )
      end
    end

    def status_detail(goal, snapshot)
      return nil if snapshot.status == "on_track"

      parts = [ "Shortfall #{money(snapshot.shortfall, goal.currency)}" ]
      parts << "required SIP #{money(snapshot.required_sip, goal.currency)} a month" if snapshot.required_sip
      parts.join(", ")
    end

    def send_monthly_summary(snapshots)
      counts = snapshots.group_by(&:status).transform_values(&:size)
      count_text = GoalSnapshot::STATUSES.filter_map { |status, label| "#{counts[status]} #{label.downcase}" if counts[status] }.join(", ")
      worst = snapshots.max_by { |snapshot| [ GoalSnapshot::SEVERITY.fetch(snapshot.status), snapshot.shortfall ] }

      body = "#{snapshots.size} #{"goal".pluralize(snapshots.size)}: #{count_text}."
      body += " #{goal_label(worst.goal)} needs the most attention." if worst.status != "on_track"
      detail = worst.status == "on_track" ? nil : status_detail(worst.goal, worst)

      users.each do |user|
        Notification.notify(
          user: user, kind: "goal_summary", title: "Your goals this month", body: body, detail: detail,
          url: url_helpers.goals_path, dedupe_key: "goal_summary:#{today.strftime("%Y-%m")}"
        )
      end
    end

    # "Rahul's Retirement" for a goal that belongs to a household member, else the goal name
    def goal_label(goal)
      goal.household_member ? "#{goal.household_member.name}'s #{goal.name}" : goal.name
    end

    def money(amount, currency)
      Money.new(amount, currency).format_compact
    end

    def url_helpers
      Rails.application.routes.url_helpers
    end
end
