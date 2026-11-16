class Property < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "residential" => { short: "Residential", long: "Residential Property" },
    "commercial" => { short: "Commercial", long: "Commercial Property" },
    "plot" => { short: "Plot", long: "Plot / Land" },
    "agricultural" => { short: "Agricultural", long: "Agricultural Land" }
  }.freeze

  has_one :address, as: :addressable, dependent: :destroy

  accepts_nested_attributes_for :address

  attribute :area_unit, :string, default: "sqft"

  class << self
    def icon
      "home"
    end

    def color
      "#06AED4"
    end

    def classification
      "asset"
    end
  end

  def area
    Measurement.new(area_value, area_unit) if area_value.present?
  end

  def purchase_price
    first_valuation_amount
  end

  def trend
    Trend.new(current: account.balance_money, previous: first_valuation_amount)
  end

  def balance_display_name
    "market value"
  end

  def opening_balance_display_name
    "original purchase price"
  end

  private
    def first_valuation_amount
      account.entries.valuations.order(:date).first&.amount_money || account.balance_money
    end
end
