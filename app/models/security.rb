class Security < ApplicationRecord
  include Provided

  # Pseudo-MIC used for Indian mutual fund schemes. Their ticker is the AMFI scheme code.
  AMFI_MIC = "AMFI".freeze
  NSE_MIC = "XNSE".freeze
  BSE_MIC = "XBOM".freeze

  KINDS = %w[stock etf mutual_fund bond gold other].freeze
  ASSET_CLASSES = %w[equity debt hybrid gold international other].freeze
  TAX_CATEGORIES = %w[equity debt other_listed other_unlisted exempt].freeze

  before_validation :upcase_symbols
  before_validation :apply_indian_defaults, on: :create

  has_many :trades, dependent: :nullify, class_name: "Trade"
  has_many :prices, dependent: :destroy
  has_many :family_security_overrides, dependent: :destroy
  has_many :goal_allocations, dependent: :destroy

  enum :kind, KINDS.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :asset_class, ASSET_CLASSES.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :tax_category, TAX_CATEGORIES.index_with(&:itself), prefix: true, validate: { allow_nil: true }

  validates :ticker, presence: true
  validates :ticker, uniqueness: { scope: :exchange_operating_mic, case_sensitive: false }

  scope :online, -> { where(offline: false) }

  # Trailing 1Y / 3Y / 5Y CAGR from the stored prices (Security::TrailingReturns)
  def trailing_returns
    @trailing_returns ||= Security::TrailingReturns.for_security(self)
  end

  def current_price
    @current_price ||= find_or_fetch_price
    return nil if @current_price.nil?
    Money.new(@current_price.price, @current_price.currency)
  end

  def amfi?
    exchange_operating_mic.to_s.upcase == AMFI_MIC
  end

  # The AMFI scheme behind a mutual fund security (ticker is the scheme code)
  def mutual_fund_scheme
    return nil unless amfi?
    @mutual_fund_scheme ||= MutualFundScheme.find_by(scheme_code: ticker)
  end

  # Human friendly name. Mutual fund tickers are numeric scheme codes, so fall back to the scheme name.
  def display_name
    name.presence || mutual_fund_scheme&.name || ticker
  end

  # Short label shown next to search results: MF / NSE / BSE
  def exchange_badge
    self.class.exchange_badge_for(exchange_operating_mic)
  end

  def self.exchange_badge_for(mic)
    case mic.to_s.upcase
    when AMFI_MIC then "MF"
    when NSE_MIC then "NSE"
    when BSE_MIC then "BSE"
    end
  end

  # Tax category for this family. A family-level override wins over the security's own category.
  def effective_tax_category(family)
    override_for(family)&.tax_category.presence || tax_category
  end

  # Asset class for this family. A family-level override wins over the security's own class.
  def effective_asset_class(family)
    override_for(family)&.asset_class.presence || asset_class
  end

  def to_combobox_option
    SynthComboboxOption.new(
      symbol: ticker,
      name: display_name,
      logo_url: logo_url,
      exchange_operating_mic: exchange_operating_mic,
      country_code: country_code,
      kind: kind
    )
  end

  private
    def override_for(family)
      return nil if family.nil?
      family_security_overrides.find_by(family_id: family.id)
    end

    def upcase_symbols
      self.ticker = ticker.upcase
      self.exchange_operating_mic = exchange_operating_mic.upcase if exchange_operating_mic.present?
    end

    # Fills in kind / ISIN / classification for Indian securities when they are first created.
    # Only touches blank attributes, so explicit values always win.
    def apply_indian_defaults
      case exchange_operating_mic
      when AMFI_MIC
        self.country_code ||= "IN"
        self.kind ||= "mutual_fund"

        if (scheme = MutualFundScheme.find_by(scheme_code: ticker))
          self.name = scheme.name if name.blank?
          self.isin ||= scheme.isin_growth.presence
          self.asset_class ||= scheme.asset_class
          self.tax_category ||= scheme.tax_category
        end
      when NSE_MIC, BSE_MIC
        self.country_code ||= "IN"
        self.kind ||= "stock"
        apply_listed_classification
      end
    end

    # Listed shares and equity ETFs are equity for tax purposes. Gold and debt ETFs are not.
    def apply_listed_classification
      label = name.to_s

      if label.match?(/\b(gold|silver)\b/i)
        self.asset_class ||= "gold"
        self.tax_category ||= "other_listed"
      elsif kind_etf? && label.match?(/\b(liquid|gilt|bond|g-?sec|sdl|debt|t-?bill|treasury)\b/i)
        self.asset_class ||= "debt"
        self.tax_category ||= "other_listed"
      else
        self.asset_class ||= "equity"
        self.tax_category ||= "equity"
      end
    end
end
