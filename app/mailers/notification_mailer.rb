# Digest of a user's unread notifications. Titles and bodies never hold amounts; the `detail` line
# (which does) is only included when the user switched "include amounts" on.
class NotificationMailer < ApplicationMailer
  def digest
    @user = params[:user]
    @notifications = params[:notifications]
    @include_amounts = params.fetch(:include_amounts) { NotificationPreference.for(@user).include_amounts? }
    @inbox_url = notifications_url
    @settings_url = settings_notifications_url

    count = @notifications.size
    mail to: @user.email, subject: "#{product_name}: #{count} #{"update".pluralize(count)} for you"
  end

  private
    # Notification URLs are app paths; emails need absolute links
    def absolute_url(path)
      path.present? ? URI.join(root_url, path).to_s : @inbox_url
    end
    helper_method :absolute_url
end
