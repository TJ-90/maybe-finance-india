# A goal's health on one day, written by MonitorGoalsJob. Comparing it with the snapshot before is
# how status changes are noticed.
class GoalSnapshot < ApplicationRecord
  STATUSES = {
    "on_track" => "On track",
    "at_risk" => "At risk",
    "off_track" => "Off track"
  }.freeze

  # Lower is healthier, used to tell a decline from a recovery
  SEVERITY = { "on_track" => 0, "at_risk" => 1, "off_track" => 2 }.freeze

  belongs_to :goal

  validates :date, presence: true, uniqueness: { scope: :goal_id }
  validates :status, inclusion: { in: STATUSES.keys }

  scope :chronological, -> { order(:date) }

  def self.status_label(status)
    STATUSES.fetch(status, status.to_s.humanize)
  end

  def status_label
    self.class.status_label(status)
  end

  def previous
    goal.goal_snapshots.where(date: ...date).order(date: :desc).first
  end

  def worse_than?(other_status)
    SEVERITY.fetch(status) > SEVERITY.fetch(other_status)
  end
end
