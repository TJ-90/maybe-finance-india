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

  # The y-axis range (in percent of the target) for the status-history chart. It follows the data, with
  # some padding, so a move from 6% to 7% fills the chart instead of looking flat. Equal values get a small
  # band around them. The range stays inside 0-100 and is never empty.
  def progress_chart_range(snapshots, min_span: 2.0)
    values = snapshots.map { |snapshot| snapshot.progress_pct.to_f.clamp(0, 100) }
    return [ 0.0, 100.0 ] if values.empty?

    low, high = values.minmax
    padding = [ (high - low) * 0.15, (min_span - (high - low)) / 2 ].max
    low -= padding
    high += padding

    # Keep the band inside 0-100 without squeezing it
    if low < 0
      high -= low
      low = 0.0
    end
    if high > 100
      low = [ low - (high - 100), 0.0 ].max
      high = 100.0
    end

    [ low, high ]
  end

  # SVG polyline points for progress over time, scaled to progress_chart_range and spread across the date
  # range. A single snapshot is drawn as one point in the middle.
  def progress_polyline_points(snapshots, width: 300, height: 80, padding: 4)
    return "" if snapshots.empty?

    low, high = progress_chart_range(snapshots)
    first = snapshots.first.date.to_time.to_i
    span = snapshots.last.date.to_time.to_i - first

    snapshots.map do |snapshot|
      x = span.zero? ? width / 2.0 : padding + (snapshot.date.to_time.to_i - first).to_f / span * (width - padding * 2)
      fraction = (snapshot.progress_pct.to_f.clamp(0, 100) - low) / (high - low)
      y = height - padding - fraction * (height - padding * 2)
      "#{x.round(1)},#{y.round(1)}"
    end.join(" ")
  end
end
