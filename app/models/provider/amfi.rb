# Reads the public AMFI "NAVAll.txt" file, which lists the latest NAV of every Indian mutual fund scheme.
#
# Format (semicolon separated, one scheme per line, grouped under category and AMC header lines):
#
#   Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date
#
#   Open Ended Schemes(Equity Scheme - Large Cap Fund)
#
#   Aditya Birla Sun Life Mutual Fund
#
#   119551;INF209KA12Z1;INF209KA13Z9;Aditya Birla Sun Life ... - Direct Plan-Growth;102.3400;01-Nov-2026
#
# A header such as `Open Ended Schemes(Equity Scheme - Large Cap Fund)` sets the category for the lines below
# it, and a bare line (no semicolons) is the AMC name.
class Provider::Amfi < Provider
  Error = Class.new(Provider::Error)

  NAVALL_URL = "https://www.amfiindia.com/spages/NAVAll.txt".freeze

  SchemeRow = Data.define(
    :scheme_code, :name, :amc, :category, :scheme_type, :plan, :option,
    :isin_growth, :isin_reinvestment, :nav, :nav_date, :asset_class, :tax_category
  )

  CATEGORY_HEADER = /\A(?<type>Open Ended|Close Ended|Closed Ended|Interval Fund)[^(]*\((?<category>.+)\)\s*\z/i
  DATA_LINE = /\A\d+;/

  class << self
    def parse_navall(io)
      new.parse_navall(io)
    end
  end

  def healthy?
    with_provider_response do
      response = client.head(NAVALL_URL)
      response.status == 200
    end
  end

  # Downloads and parses the latest NAV file
  # @return [Provider::Response] with an Array of SchemeRow
  def fetch_schemes
    with_provider_response do
      response = client.get(NAVALL_URL)
      parse_navall(StringIO.new(response.body.to_s))
    end
  end

  # Parses NAVAll.txt content. Accepts any IO (File, StringIO, uploaded file).
  # Public so the manual upload fallback in Settings can reuse it.
  # @return [Array<SchemeRow>]
  def parse_navall(io)
    amc = nil
    category = nil
    scheme_type = nil
    rows = []

    io.each_line do |raw|
      line = raw.to_s.dup.force_encoding(Encoding::UTF_8).scrub("").strip
      next if line.empty?

      if line.match?(DATA_LINE)
        row = parse_scheme_line(line, amc: amc, category: category, scheme_type: scheme_type)
        rows << row if row
      elsif line.start_with?("Scheme Code")
        next # column header
      elsif (match = CATEGORY_HEADER.match(line))
        category = match[:category].strip
        scheme_type = match[:type].strip.sub(/\s*Fund\z/i, "").sub("Closed", "Close")
      elsif !line.include?(";")
        amc = line
      end
    end

    rows
  end

  private
    def parse_scheme_line(line, amc:, category:, scheme_type:)
      code, isin_a, isin_b, name, nav, date = line.split(";", 6).map { |f| f&.strip }
      return nil if code.blank? || name.blank?

      asset_class = MutualFundScheme.infer_asset_class(category, name)

      SchemeRow.new(
        scheme_code: code,
        name: name,
        amc: amc,
        category: category,
        scheme_type: scheme_type,
        plan: MutualFundScheme.infer_plan(name),
        option: MutualFundScheme.infer_option(name),
        isin_growth: clean_isin(isin_a),
        isin_reinvestment: clean_isin(isin_b),
        nav: parse_nav(nav),
        nav_date: parse_date(date),
        asset_class: asset_class,
        tax_category: MutualFundScheme.infer_tax_category(category, name, asset_class: asset_class)
      )
    end

    def clean_isin(value)
      value = value.to_s.strip
      value.match?(/\A[A-Z]{2}[A-Z0-9]{9}\d\z/) ? value : nil
    end

    # "N.A." and "-" are published for schemes without a NAV
    def parse_nav(value)
      BigDecimal(value.to_s.delete(","))
    rescue ArgumentError, TypeError
      nil
    end

    def parse_date(value)
      Date.strptime(value.to_s, "%d-%b-%Y")
    rescue ArgumentError, TypeError
      nil
    end

    def client
      @client ||= Faraday.new(url: "https://www.amfiindia.com") do |faraday|
        faraday.request(:retry, { max: 2, interval: 0.5, interval_randomness: 0.5, backoff_factor: 2 })
        faraday.response :raise_error
        faraday.options.timeout = 60
        faraday.headers["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
      end
    end
end
