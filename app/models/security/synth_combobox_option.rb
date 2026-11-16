class Security::SynthComboboxOption
  include ActiveModel::Model

  attr_accessor :symbol, :name, :logo_url, :exchange_operating_mic, :country_code, :kind

  def id
    "#{symbol}|#{exchange_operating_mic}" # submitted by combobox as value
  end

  def to_combobox_display
    if exchange_operating_mic.to_s.upcase == Security::AMFI_MIC
      "#{name} (#{Security::AMFI_MIC} #{symbol})" # mutual fund tickers are numeric scheme codes
    else
      "#{symbol} - #{name} (#{exchange_operating_mic})" # shown in combobox input when selected
    end
  end

  # MF / NSE / BSE for Indian securities, nil otherwise
  def badge
    Security.exchange_badge_for(exchange_operating_mic)
  end
end
