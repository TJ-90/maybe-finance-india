require "test_helper"

class MutualFundSchemeTest < ActiveSupport::TestCase
  test "scheme code is unique" do
    duplicate = MutualFundScheme.new(scheme_code: "100001", name: "Dup")

    assert_not duplicate.valid?
    assert duplicate.errors[:scheme_code].any?
  end

  test "validates enum values" do
    assert_raises(ActiveRecord::RecordInvalid) { MutualFundScheme.create!(scheme_code: "1", name: "X", plan: "platinum") }
    assert_raises(ActiveRecord::RecordInvalid) { MutualFundScheme.create!(scheme_code: "2", name: "X", option: "bonus") }
  end

  test "search requires every word and matches scheme codes and ISINs" do
    assert_equal [ "100001", "100003" ], MutualFundScheme.search("alpha bluechip").order(:scheme_code).pluck(:scheme_code)
    assert_equal [ "300001" ], MutualFundScheme.search("gamma").pluck(:scheme_code)
    assert_equal [ "100001" ], MutualFundScheme.search("100001").pluck(:scheme_code)
    assert_equal [ "100001" ], MutualFundScheme.search("inf000a01001").pluck(:scheme_code)
    assert_empty MutualFundScheme.search("alpha nifty")
  end

  test "discover filters by AMC, category, plan, option and management style" do
    assert_equal 3, MutualFundScheme.discover.count
    assert_equal [ "300001" ], MutualFundScheme.discover(amc: "Gamma Sample Mutual Fund").pluck(:scheme_code)
    assert_equal [ "100001", "100003" ], MutualFundScheme.discover(category: "Equity Scheme - Large Cap Fund").order(:scheme_code).pluck(:scheme_code)
    assert_equal [ "100003" ], MutualFundScheme.discover(plan: "regular").pluck(:scheme_code)
    assert_equal [ "100003" ], MutualFundScheme.discover(option: "idcw").pluck(:scheme_code)
    assert_equal [ "300001" ], MutualFundScheme.discover(style: "passive").pluck(:scheme_code)
    assert_equal [ "100001", "100003" ], MutualFundScheme.discover(style: "active").order(:scheme_code).pluck(:scheme_code)
    assert_equal [ "100001" ], MutualFundScheme.discover(q: "bluechip", plan: "direct", style: "active").pluck(:scheme_code)
  end

  test "discover ignores unknown plan and option values and inactive schemes" do
    mutual_fund_schemes(:nifty_index).update!(active: false)

    assert_equal 2, MutualFundScheme.discover(plan: "bogus", option: "bogus").count
  end

  test "import_rows! upserts schemes from a parsed NAVAll file" do
    rows = File.open(file_fixture("navall_sample.txt")) { |io| Provider::Amfi.parse_navall(io) }

    assert_equal 16, MutualFundScheme.import_rows!(rows)

    scheme = MutualFundScheme.find_by!(scheme_code: "100001")
    assert_equal BigDecimal("245.1234"), scheme.latest_nav
    assert_equal Date.new(2026, 11, 1), scheme.nav_date
    assert_equal "Alpha Sample Mutual Fund", scheme.amc
    assert scheme.direct?
    assert_equal "equity", scheme.asset_class
    assert_equal 16, MutualFundScheme.count, "fixture schemes in the file are updated in place, not duplicated"
  end

  test "import_rows! is idempotent and only deactivates missing schemes for full files" do
    rows = File.open(file_fixture("navall_sample.txt")) { |io| Provider::Amfi.parse_navall(io) }
    MutualFundScheme.import_rows!(rows)
    MutualFundScheme.import_rows!(rows)

    assert_equal 16, MutualFundScheme.count
    assert MutualFundScheme.find_by!(scheme_code: "100003").active?

    MutualFundScheme.import_rows!(rows.first(2))
    assert MutualFundScheme.find_by!(scheme_code: "100010").active?, "partial files never deactivate schemes"

    MutualFundScheme.import_rows!(rows.first(2), deactivate_missing: true)
    assert_not MutualFundScheme.find_by!(scheme_code: "100010").active?
    assert MutualFundScheme.find_by!(scheme_code: "100001").active?
  end

  test "import_navall! rejects files that are not NAVAll.txt" do
    error = assert_raises(ArgumentError) { MutualFundScheme.import_navall!(StringIO.new("<html>not a nav file</html>")) }

    assert_match "NAVAll", error.message
  end

  test "import_navall! imports the file and records latest prices for tracked funds" do
    security = Security.create!(ticker: "100001", exchange_operating_mic: "AMFI")

    count = File.open(file_fixture("navall_sample.txt")) { |io| MutualFundScheme.import_navall!(io) }

    assert_equal 16, count
    price = security.prices.find_by(date: Date.new(2026, 11, 1))
    assert_equal BigDecimal("245.1234"), price.price
    assert_equal "INR", price.currency
  end

  test "nav_history is fetched live for untracked schemes and cached once tracked" do
    scheme = mutual_fund_schemes(:bluechip_direct)
    provider = mock("provider")
    Security.stubs(:provider).returns(provider)
    prices = [ Date.new(2026, 11, 3), Date.new(2026, 11, 4) ].map do |date|
      Provider::SecurityConcept::Price.new(symbol: "100001", date: date, price: 245, currency: "INR", exchange_operating_mic: "AMFI")
    end
    provider.stubs(:fetch_security_prices).returns(Provider::Response.new(success?: true, data: prices, error: nil))

    assert_no_difference "Security.count" do
      assert_equal [ [ Date.new(2026, 11, 3), 245 ], [ Date.new(2026, 11, 4), 245 ] ], scheme.nav_history(since: Date.new(2026, 11, 1))
    end
  end

  test "nav_history is empty without a provider" do
    Security.stubs(:provider).returns(nil)

    assert_empty mutual_fund_schemes(:bluechip_direct).nav_history
  end

  test "find_or_create_security! reuses the AMFI security" do
    scheme = mutual_fund_schemes(:bluechip_direct)

    security = scheme.find_or_create_security!

    assert_equal scheme.scheme_code, security.ticker
    assert_equal "AMFI", security.exchange_operating_mic
    assert_equal security, scheme.find_or_create_security!
    assert_equal security, scheme.security
  end

  test "classification helpers" do
    assert_equal "direct", MutualFundScheme.infer_plan("X Fund - Direct Plan - Growth")
    assert_equal "regular", MutualFundScheme.infer_plan("X Fund - Growth")
    assert_equal "idcw", MutualFundScheme.infer_option("X Fund - Regular Plan - Monthly Dividend Payout")
    assert_equal "growth", MutualFundScheme.infer_option("Dividend Yield Fund - Growth")
    assert_equal "gold", MutualFundScheme.infer_asset_class("Other Scheme - FoF Domestic", "Sample Gold Savings Fund")
    assert_equal "other", MutualFundScheme.infer_asset_class("Other Scheme - FoF Domestic", "Sample Fund of Funds")
    assert_equal "other_unlisted", MutualFundScheme.infer_tax_category("Other Scheme - FoF Overseas", "Sample Global FoF")
  end
end
