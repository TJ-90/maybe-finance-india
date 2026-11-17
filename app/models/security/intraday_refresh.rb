# Fetches the latest traded price of every NSE/BSE security somebody holds and writes (or updates)
# today's Security::Price, then re-values the accounts holding the securities that moved.
#
# Gentle with the provider (Yahoo's unofficial API): requests go out in small batches with a pause between
# them, and a batch where every request failed stops the run (rate limited or blocked), to try again at the
# next scheduled run.
class Security::IntradayRefresh
  BATCH_SIZE = 10
  BATCH_PAUSE = 1.5 # seconds
  EXCHANGE_MICS = [ Security::NSE_MIC, Security::BSE_MIC ].freeze

  def initialize(provider: Security.provider, batch_size: BATCH_SIZE, pause: BATCH_PAUSE)
    @provider = provider
    @batch_size = batch_size
    @pause = pause
  end

  # Securities that someone holds right now: listed on NSE/BSE, online, with net positive units in an account
  def self.held_securities
    held_ids = Trade.joins(:entry).group("trades.security_id").having("SUM(trades.qty) > 0").pluck("trades.security_id")

    Security.online.where(id: held_ids, exchange_operating_mic: EXCHANGE_MICS)
  end

  # Returns the ids of securities whose price for today changed
  def refresh
    return [] unless provider.respond_to?(:fetch_latest_price)

    changed_ids = []

    self.class.held_securities.to_a.each_slice(batch_size).with_index do |batch, index|
      sleep(pause) if index.positive? && pause.positive?

      results = batch.map { |security| [ security, fetch(security) ] }
      changed_ids.concat(results.filter_map { |security, price| security.id if price && store(security, price) })

      if results.none? { |_, price| price }
        Rails.logger.warn("Intraday price refresh: every request in a batch failed, backing off until the next run")
        break
      end
    end

    changed_ids
  end

  private
    attr_reader :provider, :batch_size, :pause

    def fetch(security)
      response = provider.fetch_latest_price(symbol: security.ticker, exchange_operating_mic: security.exchange_operating_mic)

      if response.success?
        response.data
      else
        Rails.logger.warn("Intraday price refresh failed for #{security.ticker}: #{response.error&.message}")
        nil
      end
    end

    # Returns true when the stored price for the day changed
    def store(security, quote)
      existing = security.prices.find_by(date: quote.date, currency: quote.currency)
      return false if existing && existing.price == quote.price

      Security::Price.upsert(
        { security_id: security.id, date: quote.date, price: quote.price, currency: quote.currency },
        unique_by: %i[security_id date currency]
      )
      true
    end
end
