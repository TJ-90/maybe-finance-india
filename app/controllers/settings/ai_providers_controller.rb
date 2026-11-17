class Settings::AiProvidersController < ApplicationController
  layout "settings"

  before_action :ensure_admin
  before_action :set_setting

  def show
  end

  def update
    attrs = setting_params
    new_key = attrs.delete(:api_key).presence

    @setting.assign_attributes(attrs)
    # A key belongs to one provider: switching provider without a new key drops the old one
    @setting.api_key = nil if new_key.nil? && @setting.provider_changed?
    @setting.api_key = new_key if new_key
    # Only keep a base URL where it applies (OpenAI and OpenRouter use their own endpoints)
    @setting.base_url = nil unless @setting.openai_compatible?
    @setting.last_test_status = @setting.last_test_message = @setting.last_tested_at = nil if @setting.api_key_changed? || @setting.base_url_changed? || @setting.provider_changed?

    if @setting.save
      redirect_to settings_ai_provider_path, notice: "AI settings saved"
    else
      render :show, status: :unprocessable_entity
    end
  end

  def test_connection
    if @setting.persisted? && (@setting.api_key? || @setting.openai_compatible?)
      status, message = @setting.test_connection!
      redirect_to settings_ai_provider_path, (status == "ok" ? { notice: message } : { alert: message })
    else
      redirect_to settings_ai_provider_path, alert: "Save an API key first, then test the connection"
    end
  end

  def remove_key
    @setting.remove_key! if @setting.persisted?
    redirect_to settings_ai_provider_path, notice: "API key removed"
  end

  private
    def ensure_admin
      redirect_to settings_profile_path, alert: "Only a family admin can change AI settings" unless Current.user.admin?
    end

    def set_setting
      @setting = Current.family.ai_provider_setting || Current.family.build_ai_provider_setting
    end

    def setting_params
      params.require(:ai_provider_setting).permit(:provider, :api_key, :base_url, :chat_model, :fast_model, :openrouter_attribution, :enabled)
    end
end
