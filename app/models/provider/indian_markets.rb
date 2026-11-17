# Composite security provider for India. Routes every call by `exchange_operating_mic`:
#
#   AMFI (mutual funds)  -> Provider::Mfapi
#   XNSE / XBOM (stocks) -> Provider::YahooFinance
#   anything else        -> the optional `fallback` provider (e.g. Synth, when the user configured a key)
#
# Search merges local mutual fund results with Yahoo equity results (and the fallback's, when it is not
# restricted to India), so one box in the trade form finds funds and NSE/BSE symbols alike.
class Provider::IndianMarkets < Provider
  include SecurityConcept

  Error = Class.new(Provider::Error)

  def initialize(mfapi: Provider::Mfapi.new, yahoo: Provider::YahooFinance.new, fallback: nil)
    @mfapi = mfapi
    @yahoo = yahoo
    @fallback = fallback
  end

  def healthy?
    with_provider_response { true }
  end

  def search_securities(symbol, country_code: nil, exchange_operating_mic: nil)
    with_provider_response do
      params = { country_code: country_code, exchange_operating_mic: exchange_operating_mic }.compact_blank
      mic = exchange_operating_mic.to_s.upcase.presence

      providers = if mic.nil?
        [ mfapi, yahoo, (fallback unless country_code.to_s.upcase == "IN") ]
      else
        [ provider_for(mic) ]
      end.compact.uniq

      responses = providers.map { |provider| provider.search_securities(symbol, **params) }
      successes = responses.select(&:success?)

      # Only fail when nothing answered, so one flaky source doesn't hide the others
      raise responses.first.error if successes.empty? && responses.any?

      successes.flat_map(&:data).uniq { |s| [ s.symbol.to_s.upcase, s.exchange_operating_mic.to_s.upcase ] }
    end
  end

  def fetch_security_info(symbol:, exchange_operating_mic:)
    route(exchange_operating_mic).fetch_security_info(symbol: symbol, exchange_operating_mic: exchange_operating_mic)
  end

  def fetch_security_price(symbol:, exchange_operating_mic:, date:)
    route(exchange_operating_mic).fetch_security_price(symbol: symbol, exchange_operating_mic: exchange_operating_mic, date: date)
  end

  # Latest traded price, for exchange-listed securities only (mutual funds publish one NAV a day)
  def fetch_latest_price(symbol:, exchange_operating_mic:)
    provider = route(exchange_operating_mic)
    return provider.fetch_security_price(symbol: symbol, exchange_operating_mic: exchange_operating_mic, date: Date.current) unless provider.respond_to?(:fetch_latest_price)

    provider.fetch_latest_price(symbol: symbol, exchange_operating_mic: exchange_operating_mic)
  end

  def fetch_security_prices(symbol:, exchange_operating_mic:, start_date:, end_date:)
    route(exchange_operating_mic).fetch_security_prices(
      symbol: symbol,
      exchange_operating_mic: exchange_operating_mic,
      start_date: start_date,
      end_date: end_date
    )
  end

  private
    attr_reader :mfapi, :yahoo, :fallback

    def provider_for(mic)
      case mic.to_s.upcase
      when ::Security::AMFI_MIC then mfapi
      when ::Security::NSE_MIC, ::Security::BSE_MIC then yahoo
      else fallback
      end
    end

    # Returns a provider-like object that always answers with a Response, even when nothing can serve the MIC
    def route(mic)
      provider_for(mic) || NoProvider.new(mic)
    end

    NoProvider = Struct.new(:mic) do
      %i[fetch_security_info fetch_security_price fetch_security_prices].each do |name|
        define_method(name) do |**_args|
          Provider::Response.new(
            success?: false,
            data: nil,
            error: Provider::IndianMarkets::Error.new("No market data provider for exchange #{mic.inspect}")
          )
        end
      end
    end
end
