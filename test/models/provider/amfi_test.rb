require "test_helper"

class Provider::AmfiTest < ActiveSupport::TestCase
  setup do
    @rows = File.open(file_fixture("navall_sample.txt")) { |io| Provider::Amfi.new.parse_navall(io) }
    @by_code = @rows.index_by(&:scheme_code)
  end

  test "parses every scheme line" do
    assert_equal 16, @rows.size
  end

  test "reads scheme fields, AMC and category from headers" do
    row = @by_code["100001"]

    assert_equal "Alpha Bluechip Fund - Direct Plan - Growth", row.name
    assert_equal "Alpha Sample Mutual Fund", row.amc
    assert_equal "Equity Scheme - Large Cap Fund", row.category
    assert_equal "Open Ended", row.scheme_type
    assert_equal "INF000A01001", row.isin_growth
    assert_equal "INF000A01002", row.isin_reinvestment
    assert_equal BigDecimal("245.1234"), row.nav
    assert_equal Date.new(2026, 11, 1), row.nav_date
  end

  test "tracks AMC changes across sections" do
    assert_equal "Beta Sample Mutual Fund", @by_code["200001"].amc
    assert_equal "Alpha Sample Mutual Fund", @by_code["100010"].amc
    assert_equal "Close Ended", @by_code["100030"].scheme_type
  end

  test "infers plan and option from the scheme name" do
    assert_equal "direct", @by_code["100001"].plan
    assert_equal "growth", @by_code["100001"].option
    assert_equal "regular", @by_code["100002"].plan
    assert_equal "idcw", @by_code["100003"].option
    assert_equal "idcw", @by_code["100011"].option
    # A fund named "Dividend Yield" is not an IDCW option
    assert_equal "growth", @by_code["200002"].option
  end

  test "treats missing ISINs and NAVs as nil" do
    assert_nil @by_code["100003"].isin_growth
    assert_nil @by_code["100011"].nav
  end

  test "infers asset class from category and name" do
    assert_equal "equity", @by_code["100001"].asset_class
    assert_equal "equity", @by_code["200001"].asset_class
    assert_equal "debt", @by_code["100010"].asset_class
    assert_equal "hybrid", @by_code["200010"].asset_class
    assert_equal "equity", @by_code["300001"].asset_class
    assert_equal "debt", @by_code["300002"].asset_class
    assert_equal "gold", @by_code["300010"].asset_class
    assert_equal "international", @by_code["300020"].asset_class
    assert_equal "debt", @by_code["100030"].asset_class
  end

  test "infers tax category" do
    assert_equal "equity", @by_code["100001"].tax_category
    assert_equal "debt", @by_code["100010"].tax_category
    assert_equal "equity", @by_code["200010"].tax_category, "aggressive hybrid is equity oriented"
    assert_equal "equity", @by_code["200011"].tax_category, "arbitrage is equity oriented"
    assert_equal "other_unlisted", @by_code["100020"].tax_category, "balanced advantage is not assumed to be equity"
    assert_equal "equity", @by_code["300001"].tax_category
    assert_equal "debt", @by_code["300002"].tax_category
    assert_equal "other_listed", @by_code["300010"].tax_category, "gold ETF units are listed"
    assert_equal "equity", @by_code["300011"].tax_category
    assert_equal "other_unlisted", @by_code["300020"].tax_category
  end

  test "class method parses too, and tolerates CRLF line endings" do
    rows = Provider::Amfi.parse_navall(StringIO.new("Open Ended Schemes(Equity Scheme - Large Cap Fund)\r\n\r\nAcme Mutual Fund\r\n\r\n900001;INF900A01001;-;Acme Fund - Direct Plan - Growth;10.5;02-Nov-2026\r\n"))

    assert_equal 1, rows.size
    assert_equal "Acme Mutual Fund", rows.first.amc
    assert_equal Date.new(2026, 11, 2), rows.first.nav_date
  end

  test "fetch_schemes downloads and parses NAVAll" do
    stub_request(:get, Provider::Amfi::NAVALL_URL).to_return(status: 200, body: file_fixture("navall_sample.txt").read)

    response = Provider::Amfi.new.fetch_schemes

    assert response.success?
    assert_equal 16, response.data.size
  end

  test "fetch_schemes returns an error response when AMFI is unreachable" do
    stub_request(:get, Provider::Amfi::NAVALL_URL).to_return(status: 503)

    response = Provider::Amfi.new.fetch_schemes

    assert_not response.success?
    assert_kind_of Provider::Amfi::Error, response.error
  end

  test "reads the current 8 column layout with separate plan and option columns" do
    rows = File.open(file_fixture("navall_current_format.txt")) { |io| Provider::Amfi.new.parse_navall(io) }
    by_code = rows.index_by(&:scheme_code)

    assert_equal 17, rows.size
    assert_equal rows.size, rows.count { |row| row.nav_date.present? }

    row = by_code["135762"]
    assert_equal BigDecimal("31.1190"), row.nav
    assert_equal Date.new(2026, 11, 16), row.nav_date
    assert_equal "direct", row.plan
    assert_equal "growth", row.option
    assert_equal "Axis Children's Fund - Direct Plan - Growth Option", row.name
    assert_equal "Axis Mutual Fund", row.amc
    assert_equal "INF846K01WO1", row.isin_growth
    assert_equal "INF846K01WQ6", by_code["135763"].isin_reinvestment

    assert_equal "regular", by_code["135759"].plan
    assert_equal "idcw", by_code["135760"].option
  end

  test "normalises plan and option wording of the current layout" do
    rows = File.open(file_fixture("navall_current_format.txt")) { |io| Provider::Amfi.new.parse_navall(io) }
    by_code = rows.index_by(&:scheme_code)

    assert_equal [ "regular", "growth" ], [ by_code["103178"].plan, by_code["103178"].option ] # "GROWTH"
    assert_equal "idcw", by_code["124832"].option # "IDCW Payout"
    assert_equal "idcw", by_code["119532"].option # "Monthly IDCW Re-investment"
  end

  test "current layout rows with empty plan and option fall back to the name" do
    rows = File.open(file_fixture("navall_current_format.txt")) { |io| Provider::Amfi.new.parse_navall(io) }
    row = rows.index_by(&:scheme_code)["148239"]

    assert_equal "UTI - Credit Risk Fund (Segregated - 06032020)", row.name
    assert_equal "regular", row.plan
    assert_equal "growth", row.option
    assert_equal BigDecimal("0"), row.nav
    assert_equal Date.new(2026, 11, 16), row.nav_date
  end
end
