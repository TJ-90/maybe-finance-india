# Runs daily after the market data refresh (see config/schedule.yml): snapshots every goal and raises
# goal status alerts and the monthly summary.
class MonitorGoalsJob < ApplicationJob
  queue_as :scheduled

  def perform(date: Date.current)
    Family.where(id: Goal.select(:family_id)).find_each do |family|
      Notification::GoalAlerts.new(family, today: date).run!
    end
  end
end
