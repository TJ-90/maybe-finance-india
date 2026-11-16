require "test_helper"

class SecurityTest < ActiveSupport::TestCase
  # Below has 3 example scenarios:
  # 1. Original ticker
  # 2. Duplicate ticker on a different exchange (different market price)
  # 3. "Offline" version of the same ticker (for users not connected to a provider)
  test "can have duplicate tickers if exchange is different" do
    original = Security.create!(ticker: "TEST", exchange_operating_mic: "XNAS")
    duplicate = Security.create!(ticker: "TEST", exchange_operating_mic: "CBOE")
    offline = Security.create!(ticker: "TEST", exchange_operating_mic: nil)

    assert original.valid?
    assert duplicate.valid?
    assert offline.valid?
  end

  test "cannot have duplicate tickers if exchange is the same" do
    original = Security.create!(ticker: "TEST", exchange_operating_mic: "XNAS")
    duplicate = Security.new(ticker: "TEST", exchange_operating_mic: "XNAS")

    assert_not duplicate.valid?
    assert_equal [ "has already been taken" ], duplicate.errors[:ticker]
  end

  test "cannot have duplicate tickers if exchange is nil" do
    original = Security.create!(ticker: "TEST", exchange_operating_mic: nil)
    duplicate = Security.new(ticker: "TEST", exchange_operating_mic: nil)

    assert_not duplicate.valid?
    assert_equal [ "has already been taken" ], duplicate.errors[:ticker]
  end

  test "casing is ignored when checking for duplicates" do
    original = Security.create!(ticker: "TEST", exchange_operating_mic: "XNAS")
    duplicate = Security.new(ticker: "tEst", exchange_operating_mic: "xNaS")

    assert_not duplicate.valid?
    assert_equal [ "has already been taken" ], duplicate.errors[:ticker]
  end

  test "effective tax category and asset class honour family overrides" do
    security = Security.create!(ticker: "HYBRID1", exchange_operating_mic: "AMFI", kind: "mutual_fund", asset_class: "hybrid", tax_category: "other_unlisted")
    family = families(:dylan_family)
    other_family = Family.create!(name: "Other", currency: "INR")

    assert_equal "other_unlisted", security.effective_tax_category(family)
    assert_equal "hybrid", security.effective_asset_class(family)

    FamilySecurityOverride.create!(family: family, security: security, tax_category: "equity")

    assert_equal "equity", security.effective_tax_category(family)
    assert_equal "hybrid", security.effective_asset_class(family), "blank override column falls back to the security"
    assert_equal "other_unlisted", security.effective_tax_category(other_family)
    assert_equal "other_unlisted", security.effective_tax_category(nil)
  end

  test "override asset class takes precedence" do
    security = Security.create!(ticker: "FOF1", exchange_operating_mic: "AMFI", asset_class: "other", tax_category: "other_unlisted")
    family = families(:dylan_family)
    FamilySecurityOverride.create!(family: family, security: security, asset_class: "debt", tax_category: "debt")

    assert_equal "debt", security.effective_asset_class(family)
    assert_equal "debt", security.effective_tax_category(family)
  end

  test "only one override per family and security" do
    security = Security.create!(ticker: "FOF2", exchange_operating_mic: "AMFI")
    family = families(:dylan_family)
    FamilySecurityOverride.create!(family: family, security: security, tax_category: "debt")

    assert_not FamilySecurityOverride.new(family: family, security: security, tax_category: "equity").valid?
  end

  test "validates kind, asset class and tax category values" do
    security = Security.new(ticker: "BAD", kind: nil)
    assert security.valid?

    assert_raises(ActiveRecord::RecordInvalid) { Security.create!(ticker: "BAD1", kind: "crypto") }
    assert_raises(ActiveRecord::RecordInvalid) { Security.create!(ticker: "BAD2", asset_class: "art") }
    assert_raises(ActiveRecord::RecordInvalid) { Security.create!(ticker: "BAD3", tax_category: "whatever") }
  end

  test "mutual fund securities pick up kind, name and classification from the scheme" do
    scheme = mutual_fund_schemes(:bluechip_direct)

    security = Security.create!(ticker: scheme.scheme_code, exchange_operating_mic: Security::AMFI_MIC)

    assert_equal "mutual_fund", security.kind
    assert_equal "IN", security.country_code
    assert_equal scheme.name, security.name
    assert_equal "INF000A01001", security.isin
    assert_equal "equity", security.asset_class
    assert_equal "equity", security.tax_category
    assert_equal scheme, security.mutual_fund_scheme
    assert_equal "MF", security.exchange_badge
  end

  test "mutual fund display name falls back to the scheme name" do
    security = Security.create!(ticker: "100001", exchange_operating_mic: "AMFI")
    security.update_columns(name: nil)

    assert_equal mutual_fund_schemes(:bluechip_direct).name, security.reload.display_name
  end

  test "NSE and BSE securities default to listed equity" do
    nse = Security.create!(ticker: "ABCD", exchange_operating_mic: "XNSE")
    gold = Security.create!(ticker: "GOLDX", exchange_operating_mic: "XBOM", name: "Sample Gold ETF", kind: "etf")

    assert_equal [ "stock", "equity", "equity", "IN", "NSE" ], [ nse.kind, nse.asset_class, nse.tax_category, nse.country_code, nse.exchange_badge ]
    assert_equal [ "gold", "other_listed", "BSE" ], [ gold.asset_class, gold.tax_category, gold.exchange_badge ]
  end

  test "US securities are left unclassified" do
    security = Security.create!(ticker: "NVDA", exchange_operating_mic: "XNAS")

    assert_nil security.kind
    assert_nil security.tax_category
  end
end
