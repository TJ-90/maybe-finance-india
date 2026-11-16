# Prices for NSE and BSE listed stocks, ETFs and Sovereign Gold Bonds from Yahoo Finance.
#
# WARNING: this uses Yahoo's *unofficial*, undocumented public endpoints. They can change, rate limit or
# disappear without notice, and Yahoo's terms restrict commercial use. The provider is deliberately tiny and
# only reachable through Provider::IndianMarkets, so it can be swapped for NSE bhavcopy or a paid feed.
#
#   Chart:  GET https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?period1=..&period2=..&interval=1d
#           => { "chart": { "result": [ { "meta": { "currency": "INR", "longName": "...", "instrumentType": "EQUITY" },
#                                          "timestamp": [..], "indicators": { "quote": [ { "close": [..] } ] } } ] } }
#   Search: GET https://query2.finance.yahoo.com/v1/finance/search?q=..
#           => { "quotes": [ { "symbol": "RELIANCE.NS", "shortname": "...", "longname": "...", "quoteType": "EQUITY" } ] }
#
# Symbols carry an exchange suffix: ".NS" for NSE (MIC XNSE) and ".BO" for BSE (MIC XBOM).
class Provider::YahooFinance < Provider
  include SecurityConcept

  Error = Class.new(Provider::Error)
  InvalidSecurityPriceError = Class.new(Error)

  CHART_URL = "https://query1.finance.yahoo.com".freeze
  SEARCH_URL = "https://query2.finance.yahoo.com".freeze
  MARKET_TIME_ZONE = "Asia/Kolkata".freeze
  SEARCH_LIMIT = 25

  SUFFIX_BY_MIC = {
    ::Security::NSE_MIC => ".NS",
    ::Security::BSE_MIC => ".BO"
  }.freeze

  MIC_BY_SUFFIX = SUFFIX_BY_MIC.invert.freeze

  KIND_BY_QUOTE_TYPE = {
    "EQUITY" => "stock",
    "ETF" => "etf"
  }.freeze

  USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36".freeze

  def healthy?
    with_provider_response do
      client(CHART_URL).get("/v8/finance/chart/RELIANCE.NS", { range: "1d", interval: "1d" }).status == 200
    end
  end

  # ================================
  #           Securities
  # ================================

  def search_securities(symbol, country_code: nil, exchange_operating_mic: nil)
    with_provider_response do
      next [] if country_code.present? && country_code.to_s.upcase != "IN"
      next [] if exchange_operating_mic.present? && !SUFFIX_BY_MIC.key?(exchange_operating_mic.to_s.upcase)

      response = client(SEARCH_URL).get("/v1/finance/search", {
        q: symbol,
        quotesCount: SEARCH_LIMIT,
        newsCount: 0,
        listsCount: 0
      })

      quotes = JSON.parse(response.body).fetch("quotes", [])

      securities = quotes.filter_map do |quote|
        yahoo_symbol = quote["symbol"].to_s.upcase
        suffix = SUFFIX_BY_MIC.values.find { |s| yahoo_symbol.end_with?(s) }
        next if suffix.nil?

        mic = MIC_BY_SUFFIX.fetch(suffix)
        next if exchange_operating_mic.present? && mic != exchange_operating_mic.to_s.upcase

        kind = KIND_BY_QUOTE_TYPE[quote["quoteType"].to_s.upcase]
        next if kind.nil? # skip indices, currencies, mutual fund pages, etc.

        Security.new(
          symbol: yahoo_symbol.delete_suffix(suffix),
          name: quote["longname"].presence || quote["shortname"],
          logo_url: nil,
          exchange_operating_mic: mic,
          country_code: "IN",
          kind: kind
        )
      end

      securities
    end
  end

  def fetch_security_info(symbol:, exchange_operating_mic:)
    with_provider_response do
      meta = fetch_chart(symbol, exchange_operating_mic, start_date: Date.current - 7.days, end_date: Date.current).fetch("meta", {})

      SecurityInfo.new(
        symbol: symbol,
        name: meta["longName"].presence || meta["shortName"],
        links: nil,
        logo_url: nil,
        description: nil,
        kind: meta["instrumentType"].to_s.downcase.presence,
        exchange_operating_mic: exchange_operating_mic.to_s.upcase
      )
    end
  end

  def fetch_security_price(symbol:, exchange_operating_mic:, date:)
    with_provider_response do
      date = date.to_date
      prices = fetch_security_prices(symbol: symbol, exchange_operating_mic: exchange_operating_mic, start_date: date - 7.days, end_date: date)

      raise Error, "No prices found for security #{symbol} on or before #{date}" if !prices.success? || prices.data.empty?

      prices.data.max_by(&:date)
    end
  end

  def fetch_security_prices(symbol:, exchange_operating_mic:, start_date:, end_date:)
    with_provider_response do
      result = fetch_chart(symbol, exchange_operating_mic, start_date: start_date.to_date, end_date: end_date.to_date)

      currency = result.dig("meta", "currency").presence || "INR"
      timestamps = result["timestamp"] || []
      closes = result.dig("indicators", "quote", 0, "close") || []
      zone = ActiveSupport::TimeZone[MARKET_TIME_ZONE]

      timestamps.each_with_index.filter_map do |timestamp, index|
        close = closes[index]
        date = zone.at(timestamp).to_date

        if close.nil? # Yahoo returns null closes for halted sessions
          Rails.logger.warn("#{self.class.name} returned no close for #{symbol} on #{date}")
          next
        end

        Price.new(
          symbol: symbol,
          date: date,
          price: BigDecimal(close.to_s),
          currency: currency,
          exchange_operating_mic: exchange_operating_mic.to_s.upcase
        )
      end.sort_by(&:date)
    end
  end

  private
    def yahoo_symbol(symbol, exchange_operating_mic)
      suffix = SUFFIX_BY_MIC[exchange_operating_mic.to_s.upcase]
      raise Error, "Unsupported exchange #{exchange_operating_mic.inspect} for Yahoo Finance" if suffix.nil?

      "#{symbol.to_s.upcase}#{suffix}"
    end

    def fetch_chart(symbol, exchange_operating_mic, start_date:, end_date:)
      zone = ActiveSupport::TimeZone[MARKET_TIME_ZONE]

      response = client(CHART_URL).get("/v8/finance/chart/#{ERB::Util.url_encode(yahoo_symbol(symbol, exchange_operating_mic))}", {
        period1: zone.local(start_date.year, start_date.month, start_date.day).to_i,
        period2: zone.local(end_date.year, end_date.month, end_date.day).end_of_day.to_i,
        interval: "1d"
      })

      body = JSON.parse(response.body)
      result = body.dig("chart", "result", 0)

      raise Error, body.dig("chart", "error", "description").presence || "Yahoo Finance returned no data for #{symbol}" if result.nil?

      result
    end

    def client(url)
      Faraday.new(url: url) do |faraday|
        faraday.request(:retry, { max: 2, interval: 0.5, interval_randomness: 0.5, backoff_factor: 2 })
        faraday.response :raise_error
        faraday.options.timeout = 20
        faraday.headers["User-Agent"] = USER_AGENT
        faraday.headers["Accept"] = "application/json"
      end
    end
end
