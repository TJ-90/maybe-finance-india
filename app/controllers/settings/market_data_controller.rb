class Settings::MarketDataController < ApplicationController
  layout "settings"

  MAX_UPLOAD_SIZE = 20.megabytes

  before_action :ensure_admin, only: :update

  def show
    load_status
  end

  # Offline fallback: import a NAVAll.txt that was downloaded from AMFI by hand
  def update
    file = params[:nav_file]

    if file.blank?
      redirect_to settings_market_data_path, alert: "Choose a NAVAll.txt file to upload"
    elsif file.size > MAX_UPLOAD_SIZE
      redirect_to settings_market_data_path, alert: "That file is too large to be an AMFI NAVAll.txt"
    else
      count = MutualFundScheme.import_navall!(file.tempfile)
      redirect_to settings_market_data_path, notice: "Imported #{count} mutual fund schemes"
    end
  rescue ArgumentError => error
    redirect_to settings_market_data_path, alert: error.message
  end

  private
    def ensure_admin
      redirect_to settings_market_data_path, alert: "Only an admin can import market data" unless Current.user.admin?
    end

    def load_status
      @scheme_count = MutualFundScheme.active.count
      @last_nav_date = MutualFundScheme.last_nav_date
      @last_scheme_sync = MutualFundScheme.maximum(:updated_at)
      @last_price_date = Security::Price.maximum(:date)
      @last_rate_date = ExchangeRate.maximum(:date)
      @indian_market_data_enabled = Provider::Registry.get_provider(:amfi).present?
      @synth_configured = Provider::Registry.get_provider(:synth).present?
    end
end
