# Exchange rates from https://www.frankfurter.app: free, keyless, European Central Bank reference rates
# (published on ECB working days, about 30 currencies including INR).
#
#   GET https://api.frankfurter.app/2026-11-02?from=USD&to=INR
#   => { "amount": 1.0, "base": "USD", "date": "2026-11-02", "rates": { "INR": 88.1 } }
#
#   GET https://api.frankfurter.app/2026-10-01..2026-10-31?from=USD&to=INR
#   => { "base": "USD", "start_date": "...", "end_date": "...", "rates": { "2026-10-01": { "INR": 88.0 }, ... } }
#
# On weekends and holidays a single-date request returns the previous working day's rate, which is what we want.
class Provider::Frankfurter < Provider
  include ExchangeRateConcept

  Error = Class.new(Provider::Error)
  InvalidExchangeRateError = Class.new(Error)

  BASE_URL = "https://api.frankfurter.app".freeze

  # Frankfurter aggregates long time series into weekly or monthly points, so we request daily-sized windows
  MAX_RANGE_DAYS = 85

  def healthy?
    with_provider_response do
      client.get("/latest", { from: "USD", to: "INR" }).status == 200
    end
  end

  def fetch_exchange_rate(from:, to:, date:)
    with_provider_response do
      next return_rate(from, to, date.to_date) if from == to

      response = client.get("/#{date.to_date.iso8601}", { from: from, to: to })
      rate = JSON.parse(response.body).dig("rates", to)

      raise InvalidExchangeRateError, "Frankfurter returned no #{from} to #{to} rate for #{date}" if rate.nil?

      Rate.new(date: date.to_date, from: from, to: to, rate: BigDecimal(rate.to_s))
    end
  end

  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    with_provider_response do
      start_date = start_date.to_date
      end_date = end_date.to_date

      next [] if start_date > end_date

      rates = []

      each_window(start_date, end_date) do |window_start, window_end|
        response = client.get("/#{window_start.iso8601}..#{window_end.iso8601}", { from: from, to: to })
        by_date = JSON.parse(response.body).fetch("rates", {})

        by_date.each do |date, values|
          rate = values.is_a?(Hash) ? values[to] : nil

          if rate.nil?
            Rails.logger.warn("#{self.class.name} returned invalid rate data for pair from: #{from} to: #{to} on: #{date}")
            next
          end

          rates << Rate.new(date: date.to_date, from: from, to: to, rate: BigDecimal(rate.to_s))
        end
      end

      rates.sort_by(&:date)
    end
  end

  private
    def return_rate(from, to, date)
      Rate.new(date: date, from: from, to: to, rate: BigDecimal("1"))
    end

    def each_window(start_date, end_date)
      cursor = start_date

      while cursor <= end_date
        window_end = [ cursor + (MAX_RANGE_DAYS - 1), end_date ].min
        yield cursor, window_end
        cursor = window_end + 1
      end
    end

    def client
      @client ||= Faraday.new(url: BASE_URL) do |faraday|
        faraday.request(:retry, { max: 2, interval: 0.5, interval_randomness: 0.5, backoff_factor: 2 })
        faraday.response :raise_error
        faraday.options.timeout = 20
        faraday.headers["Accept"] = "application/json"
      end
    end
end
