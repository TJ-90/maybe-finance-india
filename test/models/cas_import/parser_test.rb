require "test_helper"

class CasImport::ParserTest < ActiveSupport::TestCase
  def parse(name)
    CasImport::Parser.parse(file_fixture("cas/#{name}.txt").read)
  end

  test "parses a CAMS style detailed statement" do
    result = parse("cams_detailed")

    assert_equal "detailed", result.statement_type
    assert_equal Date.new(2023, 4, 1), result.period_from
    assert_equal Date.new(2024, 3, 31), result.period_to
    assert_empty result.warnings

    assert_equal 1, result.investors.size
    investor = result.investors.first
    assert_equal "ASHA KUMAR", investor[:name]
    assert_equal "XXXXX1234X", investor[:pan_masked]
    assert_equal %w[12345678/90 7000123/45], investor[:folios].map { |folio| folio[:folio_number] }
    assert_equal "Orchid Mutual Fund", investor[:folios].first[:amc]

    flexi = investor[:folios].first[:schemes].first
    assert_equal "Orchid Flexi Cap Fund - Direct Plan - Growth", flexi[:name]
    assert_equal "INF000A01AB1", flexi[:isin]
    assert_equal "CAMS", flexi[:registrar]
    assert_equal "P8046", flexi[:amc_code]
    assert_equal BigDecimal("120.96"), flexi[:closing_units]
    assert_equal BigDecimal("300"), flexi[:nav]
    assert_equal %w[sip sip redemption purchase reversal idcw_reinvest], flexi[:transactions].map { |t| t[:type] }
  end

  test "never keeps the full PAN" do
    result = parse("cams_detailed")

    refute_includes JSON.generate(result.as_json), "ABCDE1234F"
    assert_equal "XXXXX1234X", CasImport::Parser.mask_pan("ABCDE1234F")
  end

  test "attaches stamp duty and STT to the parent transaction instead of making trades" do
    flexi = parse("cams_detailed").schemes.first

    assert_equal 6, flexi[:transactions].size
    assert_equal BigDecimal("0.25"), flexi[:transactions][0][:stamp_duty]
    assert_equal BigDecimal("0.06"), flexi[:transactions][2][:stt]
  end

  test "units add up to the closing balance for every scheme" do
    %w[cams_detailed kfintech_detailed].each do |name|
      result = parse(name)

      result.schemes.each do |scheme|
        movement = scheme[:transactions].sum(BigDecimal("0")) { |t| CasImport::Parser.signed_units(t) }
        assert_equal scheme[:closing_units], (scheme[:opening_units] || 0) + movement, "#{name}: #{scheme[:name]}"
      end
    end
  end

  test "reads switches, IDCW and negative amounts in parentheses" do
    transactions = parse("cams_detailed").transactions

    assert_equal %w[switch_in switch_out], transactions.map { |t| t[:type] }.select { |t| t.start_with?("switch") }.first(2)
    assert_includes transactions.map { |t| t[:type] }, "idcw_payout"
    redemption = transactions.find { |t| t[:type] == "redemption" }
    assert_equal BigDecimal("-25"), redemption[:units]
    assert_equal(-BigDecimal("25"), CasImport::Parser.signed_units(redemption))
  end

  test "reversal of a purchase takes units away" do
    reversal = parse("cams_detailed").transactions.find { |t| t[:type] == "reversal" }

    assert_equal(-BigDecimal("12"), CasImport::Parser.signed_units(reversal))
  end

  test "parses a KFintech style statement with spaced separators" do
    result = parse("kfintech_detailed")

    assert_equal "RAVI MENON", result.investors.first[:name]
    assert_equal "XXXXX5678X", result.investors.first[:pan_masked]
    assert_equal %w[99887766 5544332/01], result.investors.first[:folios].map { |f| f[:folio_number] }
    assert_equal BigDecimal("0.6"), result.transactions.first[:stamp_duty]
    assert_equal %w[purchase sip sip redemption idcw_reinvest idcw_payout switch_out], result.transactions.map { |t| t[:type] }
    assert_equal BigDecimal("50"), result.schemes.last[:opening_units]
    assert_empty result.warnings
  end

  test "parses a summary statement" do
    result = parse("summary")

    assert result.summary?
    assert_equal Date.new(2024, 3, 31), result.as_on
    assert_equal 2, result.schemes.size
    assert_equal BigDecimal("25000"), result.schemes.first[:cost_value]
    assert_equal BigDecimal("21"), result.schemes.last[:closing_units]
    assert_empty result.transactions
  end

  test "warns when units do not reconcile" do
    text = file_fixture("cas/cams_detailed.txt").read.sub("Closing Unit Balance: 21.000", "Closing Unit Balance: 22.000")

    result = CasImport::Parser.parse(text)

    assert result.warnings.any? { |warning| warning.include?("don't add up") }
  end

  test "returns nothing for unrelated text" do
    result = CasImport::Parser.parse("hello\nworld")

    assert_empty result.investors
  end
end
