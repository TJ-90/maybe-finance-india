# Runs daily (see config/schedule.yml): raises stale-data, stale-NAV, insurance premium and year-end tax
# reminders for every user. Each reminder is deduplicated, so running it again is harmless.
class SendRemindersJob < ApplicationJob
  queue_as :scheduled

  def perform(date: Date.current)
    User.where(active: true).find_each do |user|
      Notification::Reminders.new(user, today: date).run!
    end
  end
end
