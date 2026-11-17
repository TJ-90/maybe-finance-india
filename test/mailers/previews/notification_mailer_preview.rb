# Preview at /rails/mailers/notification_mailer. Run it with the amounts switched off and on.
class NotificationMailerPreview < ActionMailer::Preview
  def digest_without_amounts
    build_digest(include_amounts: false)
  end

  def digest_with_amounts
    build_digest(include_amounts: true)
  end

  private
    def build_digest(include_amounts:)
      user = User.first
      notifications = [
        Notification.new(
          user: user, family: user.family, kind: "goal_status", title: "Home down payment is at risk",
          body: "Status changed from on track to at risk. Review the monthly SIP or the money allocated to this goal.",
          detail: "Shortfall ₹1.2L, required SIP ₹18K a month", url: "/goals"
        ),
        Notification.new(
          user: user, family: user.family, kind: "premium_due", title: "Star Health health premium is due in 5 days",
          body: "Due on 21 Nov 2026.", detail: "Premium ₹24K", url: "/insurance_policies"
        )
      ]

      NotificationMailer.with(user: user, notifications: notifications, include_amounts: include_amounts).digest
    end
end
