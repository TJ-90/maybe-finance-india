class PreciousMetalsController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id, :weight_grams, :purity, :form, :price_per_gram
  )

  private
    # "Price per gram x weight x purity" turns into the account balance: the opening value when
    # the account is created, a new valuation when it is edited. The price is not stored.
    def account_params
      super.tap do |permitted|
        attrs = permitted[:accountable_attributes]
        next if attrs.blank?

        if permitted[:balance].blank?
          permitted[:balance] = estimated_balance(attrs) || (action_name == "create" ? 0 : nil)
        end
      end
    end

    def estimated_balance(attrs)
      price = attrs[:price_per_gram]
      return nil if price.blank?

      weight = attrs[:weight_grams].presence || @account&.precious_metal&.weight_grams
      return nil if weight.blank?

      purity = attrs[:purity].presence || @account&.precious_metal&.purity || "24k"

      PreciousMetal.estimate_value(price_per_gram: price, weight_grams: weight, purity: purity)
    end
end
