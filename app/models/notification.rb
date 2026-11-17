# An in-app reminder for one user (bell and inbox), optionally repeated in an emailed digest.
#
# Jobs run every day, so every notification that is raised on a schedule carries a dedupe_key such as
# "stale_account:<account_id>:2026-11". A user never gets two notifications with the same key, which
# is what keeps repeated runs from spamming.
#
# Privacy: `title` and `body` never contain amounts, so they are always safe to email. `detail` holds
# the figures and is only shown in the app, or in an email when the user switched amounts on.
class Notification < ApplicationRecord
  KINDS = {
    "goal_status" => "Goal status changes",
    "goal_summary" => "Monthly goal summary",
    "stale_account" => "Investment accounts needing an update",
    "stale_navs" => "Stale mutual fund NAVs",
    "premium_due" => "Insurance premiums due",
    "tax_year_end" => "Year-end tax review"
  }.freeze

  # Notifications older than this are not emailed, e.g. when a user opts in long after they were raised
  DIGEST_WINDOW = 3.days

  belongs_to :user
  belongs_to :family

  validates :kind, inclusion: { in: KINDS.keys }
  validates :title, presence: true
  validates :dedupe_key, uniqueness: { scope: :user_id }, allow_nil: true

  scope :unread, -> { where(read_at: nil) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :unemailed, -> { where(emailed_at: nil) }

  class << self
    # Creates the notification unless the user turned that kind off or already has one with the
    # same dedupe key. Returns the new record, or nil when nothing was created.
    def notify(user:, kind:, title:, body: nil, detail: nil, url: nil, dedupe_key: nil)
      return nil unless NotificationPreference.for(user).kind_enabled?(kind)
      return nil if dedupe_key.present? && where(user: user, dedupe_key: dedupe_key).exists?

      create!(user: user, family: user.family, kind: kind, title: title, body: body, detail: detail, url: url, dedupe_key: dedupe_key)
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # Emails the user's recent unread notifications once, then marks them as emailed. Returns the
    # number of notifications sent; zero when the user hasn't opted in or the server can't send mail.
    def deliver_digest(preferences)
      return 0 unless preferences.email_deliverable?

      pending = preferences.user.notifications.unread.unemailed.where(created_at: DIGEST_WINDOW.ago..).newest_first.to_a
      return 0 if pending.empty?

      NotificationMailer.with(user: preferences.user, notifications: pending).digest.deliver_now
      where(id: pending.map(&:id)).update_all(emailed_at: Time.current)
      pending.size
    end

    # Email is only possible when the server has SMTP settings (the production config reads them
    # from these variables).
    def email_delivery_configured?
      ENV["SMTP_ADDRESS"].present?
    end
  end

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.current) unless read?
  end
end
