# Switches and clocks shared by the market data jobs (see config/schedule.yml).
module MarketData
  TIME_ZONE = "Asia/Kolkata".freeze

  # NSE/BSE regular session, IST
  OPENS_AT = [ 9, 15 ].freeze
  CLOSES_AT = [ 15, 30 ].freeze

  class << self
    # "Refresh prices now": the same jobs the schedule runs, queued immediately (also in development).
    # AMFI NAVs first, and the NSE/BSE latest closes; both chain RefreshInvestmentValuesJob afterwards.
    def refresh_now
      ImportMutualFundSchemesJob.perform_later(manual: true)
      ImportMarketDataJob.perform_later({ "mode" => "full", "scope" => "exchange_close", "manual" => true })
    end

    # "Prices as of 4 Nov 2026, 4:15 PM IST"
    def format_prices_as_of(time)
      return nil if time.nil?

      "Prices as of #{time.in_time_zone(TIME_ZONE).strftime('%-d %b %Y, %-l:%M %p')} IST"
    end

    # Scheduled jobs are skipped in development unless ENABLE_MARKET_DATA_IN_DEV=true
    def jobs_enabled?
      !Rails.env.development? || ENV["ENABLE_MARKET_DATA_IN_DEV"] == "true"
    end

    # INTRADAY_PRICE_REFRESH defaults to true; "false" turns the 15-minute refresh off
    def intraday_enabled?
      ENV.fetch("INTRADAY_PRICE_REFRESH", "true").to_s.downcase != "false"
    end

    # Whether the NSE/BSE regular session is on (weekdays 09:15-15:30 IST, judged in IST whatever the
    # server zone is). Exchange holidays are not known here; a holiday simply yields unchanged prices.
    def market_open?(time = Time.current)
      ist = time.in_time_zone(TIME_ZONE)
      return false if ist.saturday? || ist.sunday?

      minutes = ist.hour * 60 + ist.min
      minutes.between?(OPENS_AT[0] * 60 + OPENS_AT[1], CLOSES_AT[0] * 60 + CLOSES_AT[1])
    end
  end
end
