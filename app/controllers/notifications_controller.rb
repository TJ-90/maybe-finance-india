class NotificationsController < ApplicationController
  PER_PAGE = 50

  before_action :set_notification, only: %i[update open]

  def index
    @notifications = Current.user.notifications.newest_first.limit(PER_PAGE)
    @unread_count = Current.user.unread_notifications_count
    @breadcrumbs = [ [ "Home", root_path ], [ "Notifications", nil ] ]
  end

  def update
    @notification.mark_read!
    redirect_back_or_to notifications_path
  end

  # Marks the notification as read and goes to the page it is about
  def open
    @notification.mark_read!
    redirect_to local_path(@notification.url) || notifications_path
  end

  def mark_all_read
    Current.user.notifications.unread.update_all(read_at: Time.current, updated_at: Time.current)
    redirect_to notifications_path, notice: "All notifications marked as read"
  end

  private
    def set_notification
      @notification = Current.user.notifications.find(params[:id])
    end

    # Only ever redirect inside the app
    def local_path(url)
      url if url.to_s.start_with?("/") && !url.to_s.start_with?("//")
    end
end
