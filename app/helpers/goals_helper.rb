module GoalsHelper
  STATUS_BADGE_CLASSES = {
    "on_track" => "bg-success/10 text-success",
    "at_risk" => "bg-warning/10 text-warning",
    "off_track" => "bg-destructive/10 text-destructive"
  }.freeze

  def goal_status_badge(status)
    tag.span GoalSnapshot.status_label(status),
             class: "shrink-0 text-xs font-medium rounded-full px-2 py-0.5 #{STATUS_BADGE_CLASSES.fetch(status, STATUS_BADGE_CLASSES["off_track"])}"
  end

  # SVG polyline points for progress over time (0-100%), spread across the date range
  def progress_polyline_points(snapshots, width: 300, height: 80, padding: 4)
    return "" if snapshots.size < 2

    first = snapshots.first.date.to_time.to_i
    span = [ snapshots.last.date.to_time.to_i - first, 1 ].max

    snapshots.map do |snapshot|
      x = padding + (snapshot.date.to_time.to_i - first).to_f / span * (width - padding * 2)
      y = height - padding - snapshot.progress_pct.to_f.clamp(0, 100) / 100 * (height - padding * 2)
      "#{x.round(1)},#{y.round(1)}"
    end.join(" ")
  end
end
