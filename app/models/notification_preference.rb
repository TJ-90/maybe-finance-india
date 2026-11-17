# Per-user notification settings (Settings -> Notifications). A user without a row gets the
# defaults, so rows are only written when the user saves the form.
class NotificationPreference < ApplicationRecord
  DEFAULT_STALE_DATA_DAYS = 35

  belongs_to :user

  validates :stale_data_days, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 365 }

  normalizes :disabled_kinds, with: ->(kinds) { Array(kinds).map(&:to_s).reject(&:blank?).uniq }

  class << self
    def for(user)
      find_by(user: user) || new(user: user)
    end
  end

  # The monthly summary has its own switch; every other kind is switched off through disabled_kinds
  def kind_enabled?(kind)
    return monthly_summary? if kind.to_s == "goal_summary"

    disabled_kinds.exclude?(kind.to_s)
  end

  # Kinds the user can toggle one by one
  def self.toggleable_kinds
    Notification::KINDS.except("goal_summary")
  end

  # Takes the form's list of enabled kinds and stores the rest as disabled
  def enabled_kinds=(kinds)
    enabled = Array(kinds).map(&:to_s)
    self.disabled_kinds = self.class.toggleable_kinds.keys - enabled
  end

  # Emails go out only when the user opted in and the server can actually send mail
  def email_deliverable?
    email_enabled? && Notification.email_delivery_configured?
  end
end
