# Historical NAVs for Indian mutual funds from https://www.mfapi.in (free, keyless).
#
#   GET https://api.mfapi.in/mf/{scheme_code}
#   => { "meta": { "scheme_name": "...", "fund_house": "...", "scheme_code": 119551, ... },
#        "data": [ { "date": "01-11-2026", "nav": "102.34000" }, ... ],   # newest first
#        "status": "SUCCESS" }
#
# Search never goes over the network: it queries the local `mutual_fund_schemes` table, which is filled from
# AMFI's NAVAll.txt (see Provider::Amfi and ImportMutualFundSchemesJob).
class Provider::Mfapi < Provider
  include SecurityConcept

  Error = Class.new(Provider::Error)
  InvalidSecurityPriceError = Class.new(Error)

  BASE_URL = "https://api.mfapi.in".freeze
  CURRENCY = "INR".freeze
  SEARCH_LIMIT = 25

  def healthy?
    with_provider_response do
      client.get("/mf/latest").status == 200
    end
  end

  # ================================
  #           Securities
  # ================================

  def search_securities(symbol, country_code: nil, exchange_operating_mic: nil)
    with_provider_response do
      next [] unless handles?(country_code: country_code, exchange_operating_mic: exchange_operating_mic)

      MutualFundScheme.active.search(symbol).alphabetically.limit(SEARCH_LIMIT).map do |scheme|
        Security.new(
          symbol: scheme.scheme_code,
          name: scheme.name,
          logo_url: nil,
          exchange_operating_mic: ::Security::AMFI_MIC,
          country_code: "IN",
          kind: "mutual_fund"
        )
      end
    end
  end

  def fetch_security_info(symbol:, exchange_operating_mic: nil)
    with_provider_response do
      scheme = MutualFundScheme.find_by(scheme_code: symbol)

      name = scheme&.name
      name ||= fetch_nav_payload(symbol).dig("meta", "scheme_name")

      raise Error, "Unknown mutual fund scheme #{symbol}" if name.blank?

      SecurityInfo.new(
        symbol: symbol,
        name: name,
        links: nil,
        logo_url: nil,
        description: scheme&.category,
        kind: "mutual fund",
        exchange_operating_mic: ::Security::AMFI_MIC
      )
    end
  end

  # Funds publish no NAV on market holidays, so this returns the latest NAV on or before `date`
  # (looking back up to 10 days).
  def fetch_security_price(symbol:, exchange_operating_mic: nil, date:)
    with_provider_response do
      date = date.to_date
      prices = fetch_security_prices(symbol: symbol, exchange_operating_mic: exchange_operating_mic, start_date: date - 10.days, end_date: date)

      raise Error, "No prices found for scheme #{symbol} on or before #{date}" if !prices.success? || prices.data.empty?

      prices.data.max_by(&:date)
    end
  end

  def fetch_security_prices(symbol:, exchange_operating_mic: nil, start_date:, end_date:)
    with_provider_response do
      payload = fetch_nav_payload(symbol)
      start_date = start_date.to_date
      end_date = end_date.to_date

      (payload["data"] || []).filter_map do |point|
        date = parse_date(point["date"])
        nav = parse_nav(point["nav"])

        if date.nil? || nav.nil?
          Rails.logger.warn("#{self.class.name} returned invalid NAV data for scheme #{symbol}: #{point.inspect}")
          next
        end

        next unless date.between?(start_date, end_date)

        Price.new(
          symbol: symbol,
          date: date,
          price: nav,
          currency: CURRENCY,
          exchange_operating_mic: ::Security::AMFI_MIC
        )
      end.sort_by(&:date)
    end
  end

  private
    def handles?(country_code:, exchange_operating_mic:)
      return false if country_code.present? && country_code.to_s.upcase != "IN"
      return false if exchange_operating_mic.present? && exchange_operating_mic.to_s.upcase != ::Security::AMFI_MIC

      true
    end

    def fetch_nav_payload(symbol)
      response = client.get("/mf/#{ERB::Util.url_encode(symbol.to_s)}")
      payload = JSON.parse(response.body)

      raise Error, "MFAPI returned no data for scheme #{symbol}" unless payload.is_a?(Hash) && payload["data"].is_a?(Array)

      payload
    end

    # MFAPI dates look like "01-11-2026"
    def parse_date(value)
      Date.strptime(value.to_s, "%d-%m-%Y")
    rescue ArgumentError
      nil
    end

    def parse_nav(value)
      nav = BigDecimal(value.to_s)
      nav.positive? ? nav : nil
    rescue ArgumentError
      nil
    end

    def client
      @client ||= Faraday.new(url: BASE_URL) do |faraday|
        faraday.request(:retry, { max: 2, interval: 0.5, interval_randomness: 0.5, backoff_factor: 2 })
        faraday.response :raise_error
        faraday.options.timeout = 30
        faraday.headers["Accept"] = "application/json"
      end
    end
end
