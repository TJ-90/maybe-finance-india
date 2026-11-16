require "test_helper"

class PreciousMetalTest < ActiveSupport::TestCase
  test "value is price per gram x weight x purity factor" do
    # 10 g of 22K at 7,000 per gram of 24K: 7,000 x 10 x 22/24
    assert_in_delta 64_166.67, PreciousMetal.estimate_value(price_per_gram: 7_000, weight_grams: 10, purity: "22k"), 0.01
    assert_equal 70_000, PreciousMetal.estimate_value(price_per_gram: 7_000, weight_grams: 10, purity: "24k")
    assert_equal 6_993, PreciousMetal.estimate_value(price_per_gram: 100, weight_grams: 70, purity: "999")
  end

  test "defaults to 24K when the purity is unknown" do
    assert_equal 1, PreciousMetal.purity_factor(nil)
  end

  test "estimates from its own weight and purity" do
    metal = PreciousMetal.new(weight_grams: 50, purity: "18k")

    assert_equal 262_500, metal.estimated_value(7_000) # 7,000 x 50 x 0.75
  end

  test "rejects an unknown purity or form" do
    assert_not PreciousMetal.new(purity: "10k").valid?
    assert_not PreciousMetal.new(form: "ingots").valid?
    assert PreciousMetal.new(purity: "22k", form: "coins", weight_grams: 10).valid?
  end
end
