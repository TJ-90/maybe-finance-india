class Settings::NotificationsController < ApplicationController
  layout "settings"

  def show
    @preferences = NotificationPreference.for(Current.user)
    @email_available = Notification.email_delivery_configured?
  end

  def update
    @preferences = NotificationPreference.for(Current.user)

    if @preferences.update(preference_params)
      redirect_to settings_notifications_path, notice: "Notification settings saved"
    else
      @email_available = Notification.email_delivery_configured?
      render :show, status: :unprocessable_entity
    end
  end

  private
    def preference_params
      params.require(:notification_preference).permit(
        :email_enabled, :include_amounts, :monthly_summary, :stale_data_days, enabled_kinds: []
      )
    end
end
