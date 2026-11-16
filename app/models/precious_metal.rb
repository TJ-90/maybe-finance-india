class PreciousMetal < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "gold" => { short: "Gold", long: "Gold" },
    "silver" => { short: "Silver", long: "Silver" }
  }.freeze

  # Share of pure metal. Quote prices are for 24k gold / 999 silver.
  PURITIES = {
    "24k" => { label: "24K (99.9%)", factor: BigDecimal("1") },
    "22k" => { label: "22K (91.6%)", factor: BigDecimal("22") / 24 },
    "18k" => { label: "18K (75%)", factor: BigDecimal("18") / 24 },
    "999" => { label: "999 (99.9%)", factor: BigDecimal("0.999") },
    "925" => { label: "925 sterling (92.5%)", factor: BigDecimal("0.925") }
  }.freeze

  FORMS = {
    "coins" => "Coins",
    "bars" => "Bars",
    "jewellery" => "Jewellery"
  }.freeze

  # Not stored: used by the form to turn "price per gram x weight x purity" into a valuation
  attr_accessor :price_per_gram

  validates :weight_grams, numericality: { greater_than: 0 }, allow_nil: true
  validates :purity, inclusion: { in: PURITIES.keys }, allow_blank: true
  validates :form, inclusion: { in: FORMS.keys }, allow_blank: true

  class << self
    def color
      "#D97706"
    end

    def icon
      "gem"
    end

    def classification
      "asset"
    end

    def purity_factor(purity)
      PURITIES.fetch(purity.to_s) { PURITIES["24k"] }.fetch(:factor)
    end

    # price_per_gram is the market price for 24k gold (or 999 silver); this scales it to the item's purity
    def estimate_value(price_per_gram:, weight_grams:, purity: "24k")
      (price_per_gram.to_d * weight_grams.to_d * purity_factor(purity)).round(2)
    end
  end

  def estimated_value(price_per_gram)
    self.class.estimate_value(price_per_gram: price_per_gram, weight_grams: weight_grams, purity: purity || "24k")
  end

  def balance_display_name
    "market value"
  end

  def opening_balance_display_name
    "purchase value"
  end

  def trend
    Trend.new(current: account.balance_money, previous: account.first_valuation_amount)
  end
end
