require "test_helper"

class TaxCenter::RulesTest < ActiveSupport::TestCase
  setup do
    @rules = TaxCenter::Rules.current
  end

  def classify(category, buy, sell)
    @rules.classify(category: category, buy_date: Date.parse(buy), sell_date: Date.parse(sell))
  end

  def assert_result(result, term:, bucket:, rate:)
    assert_equal term, result.term
    assert_equal bucket, result.bucket
    rate.nil? ? assert_nil(result.rate) : assert_equal(BigDecimal(rate.to_s), result.rate)
  end

  test "config is data with a verification header" do
    assert_match(/Verify each financial year/, File.read(TaxCenter::Rules::CONFIG_PATH).lines.first)
  end

  # Equity: 12 months, 15/10% before 2024-07-23 and 20/12.5% from then on
  test "equity holding period threshold is more than 12 months" do
    assert_result classify("equity", "2023-01-15", "2024-01-15"), term: :short, bucket: :stcg_equity, rate: 15
    assert_result classify("equity", "2023-01-15", "2024-01-16"), term: :long, bucket: :ltcg_equity, rate: 10
  end

  test "equity rates change for transfers on or after 2024-07-23" do
    assert_result classify("equity", "2024-06-01", "2024-07-22"), term: :short, bucket: :stcg_equity, rate: 15
    assert_result classify("equity", "2024-06-01", "2024-07-23"), term: :short, bucket: :stcg_equity, rate: 20
    assert_result classify("equity", "2022-01-01", "2024-07-22"), term: :long, bucket: :ltcg_equity, rate: 10
    assert_result classify("equity", "2022-01-01", "2024-07-23"), term: :long, bucket: :ltcg_equity, rate: 12.5
  end

  test "only long term equity gains are eligible for the exemption" do
    assert classify("equity", "2022-01-01", "2025-01-01").exemption_eligible
    assert_not classify("equity", "2024-06-01", "2025-01-01").exemption_eligible
    assert_not classify("other_unlisted", "2020-01-01", "2025-01-01").exemption_eligible
  end

  test "equity lots bought on or before 2018-01-31 carry a grandfathering warning" do
    old = classify("equity", "2018-01-31", "2025-01-01")
    newer = classify("equity", "2018-02-01", "2025-01-01")

    assert old.grandfathering_warning
    assert_match(/grandfathered cost/, old.notes.join)
    assert_not newer.grandfathering_warning
  end

  # Debt: slab for lots bought on or after 2023-04-01, otherwise like other_unlisted
  test "debt lots bought on or after 2023-04-01 are always slab taxed" do
    result = classify("debt", "2023-04-01", "2026-06-01")

    assert_result result, term: :short, bucket: :slab, rate: nil
    assert_not result.exemption_eligible
    assert_match(/50AA/, result.notes.join)
  end

  test "debt lots bought before 2023-04-01 follow the other unlisted rules" do
    # 36 months before 2024-07-23
    assert_result classify("debt", "2020-01-01", "2023-01-01"), term: :short, bucket: :slab, rate: nil
    assert_result classify("debt", "2020-01-01", "2023-01-02"), term: :long, bucket: :ltcg_other, rate: 20
    # 24 months from 2024-07-23
    assert_result classify("debt", "2023-03-31", "2025-03-31"), term: :short, bucket: :slab, rate: nil
    assert_result classify("debt", "2023-03-31", "2025-04-01"), term: :long, bucket: :ltcg_other, rate: 12.5
  end

  # Other unlisted: 36 months at 20% (indexation) before 2024-07-23, 24 months at 12.5% after
  test "other unlisted needs more than 36 months before 2024-07-23" do
    assert_result classify("other_unlisted", "2020-01-01", "2023-01-01"), term: :short, bucket: :slab, rate: nil
    long = classify("other_unlisted", "2020-01-01", "2023-01-02")
    assert_result long, term: :long, bucket: :ltcg_other, rate: 20
    assert_match(/Indexation is not computed/, long.notes.join)
  end

  test "other unlisted needs more than 24 months from 2024-07-23" do
    assert_result classify("other_unlisted", "2022-08-01", "2024-08-01"), term: :short, bucket: :slab, rate: nil
    assert_result classify("other_unlisted", "2022-08-01", "2024-08-02"), term: :long, bucket: :ltcg_other, rate: 12.5
  end

  test "the 24 month rule applies to a sale on 2024-07-23 but not the day before" do
    assert_result classify("other_unlisted", "2022-01-01", "2024-07-22"), term: :short, bucket: :slab, rate: nil
    assert_result classify("other_unlisted", "2022-01-01", "2024-07-23"), term: :long, bucket: :ltcg_other, rate: 12.5
  end

  # Other listed: 12 months at 12.5% from 2024-07-23
  test "other listed needs more than 12 months from 2024-07-23" do
    assert_result classify("other_listed", "2023-08-01", "2024-08-01"), term: :short, bucket: :slab, rate: nil
    assert_result classify("other_listed", "2023-08-01", "2024-08-02"), term: :long, bucket: :ltcg_other, rate: 12.5
  end

  test "exempt securities have no tax" do
    result = classify("exempt", "2018-01-01", "2026-01-01")

    assert result.exempt?
    assert_equal 0, result.rate
  end

  test "a missing category is treated as other unlisted with a note" do
    result = classify(nil, "2020-01-01", "2025-01-01")

    assert_equal "other_unlisted", result.category
    assert_match(/No tax category/, result.notes.join)
  end

  test "the exemption is 1 lakh up to FY 2023-24 and 1.25 lakh from FY 2024-25" do
    assert_equal 100_000, @rules.ltcg_equity_exemption(Date.new(2023, 4, 1))
    assert_equal 125_000, @rules.ltcg_equity_exemption(Date.new(2024, 4, 1))
    assert_equal 125_000, @rules.ltcg_equity_exemption(Date.new(2026, 4, 1))
  end
end
