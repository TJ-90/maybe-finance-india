# Runs daily (see config/schedule.yml): emails each opted-in user the notifications they haven't read
# yet. Does nothing when the server has no SMTP settings.
class SendNotificationDigestsJob < ApplicationJob
  queue_as :scheduled

  def perform
    return unless Notification.email_delivery_configured?

    NotificationPreference.where(email_enabled: true).includes(:user).find_each do |preferences|
      Notification.deliver_digest(preferences)
    end
  end
end
