require "test_helper"

class BrokerTradebookImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @family = families(:dylan_family)
    @account = @family.accounts.create!(name: "Demat", balance: 0, currency: "INR", accountable: Investment.new, subtype: "demat")
  end

  def build_import(fixture, preset: nil, date_format: nil)
    import = @family.imports.create!(type: "BrokerTradebookImport", account: @account, number_format: "1,234.56")
    import.update!(raw_file_str: file_fixture("imports/india/#{fixture}").read, broker_preset: preset)
    import.update!(date_format: date_format || import.preset.date_format)
    import.generate_rows_from_csv
    import.reload
  end

  test "detects the Zerodha layout and imports equity buys and sells" do
    import = build_import("zerodha_tradebook.csv")

    assert_equal "zerodha_console", import.preset.key
    # the futures line is skipped
    assert_equal 4, import.rows.count

    infy = Security.create!(ticker: "INFY", exchange_operating_mic: "XNSE", isin: "INE009A01021")
    reliance = Security.create!(ticker: "RELIANCE", exchange_operating_mic: "XNSE")
    sampleco = Security.create!(ticker: "SAMPLECO", exchange_operating_mic: "XBOM")

    assert_difference -> { Trade.count } => 4 do
      import.publish
    end

    assert_equal "complete", import.status

    assert_equal [ 10, 5 ], Trade.where(security: reliance).order(:external_id).map { |t| t.qty.to_i }
    assert_equal "INE002A01018", reliance.reload.isin

    sell = Trade.find_by!(security: infy)
    assert_equal(-5, sell.qty)
    assert_equal "81234999", sell.external_id
    assert_equal(-BigDecimal("8250"), sell.entry.amount)
    assert_equal "XBOM", Trade.find_by!(external_id: "81235111").security.exchange_operating_mic
    assert_equal sampleco, Trade.find_by!(external_id: "81235111").security
  end

  test "re-importing a tradebook skips trades with a known trade id" do
    import = build_import("zerodha_tradebook.csv")
    import.publish

    again = build_import("zerodha_tradebook.csv")

    assert_equal({ transactions: 0, already_imported: 4 }, again.dry_run)
    assert_no_difference -> { Trade.count } do
      again.publish
    end
  end

  test "resolves securities by ISIN on the same exchange before using the resolver" do
    existing = Security.create!(ticker: "RELIANCE-OLD", exchange_operating_mic: "XNSE", isin: "INE002A01018")
    Security::Resolver.expects(:new).with("INFY", exchange_operating_mic: "XNSE").returns(stub(resolve: Security.create!(ticker: "INFY", exchange_operating_mic: "XNSE")))
    Security::Resolver.expects(:new).with("SAMPLECO", exchange_operating_mic: "XBOM").returns(stub(resolve: Security.create!(ticker: "SAMPLECO", exchange_operating_mic: "XBOM")))

    build_import("zerodha_tradebook.csv").publish

    assert_equal 2, Trade.where(security: existing).count
  end

  test "skips non equity segments" do
    import = build_import("zerodha_tradebook.csv")

    assert_not_includes import.rows.map(&:ticker), "NIFTY24MARFUT"
  end

  test "mutual fund template imports units with folio and amount" do
    MutualFundScheme.create!(scheme_code: "555001", name: "Orchid Flexi Cap Fund", isin_growth: "INF000A01AB1")
    import = build_import("mf_template.csv", preset: "mf_template")

    assert_equal 3, import.rows.count
    import.publish

    assert_equal "complete", import.status
    # Row 1 names the scheme by AMFI code (a fixture scheme); row 2 by ISIN
    bluechip = Security.find_by!(ticker: "100001", exchange_operating_mic: "AMFI")
    flexi = Security.find_by!(ticker: "555001", exchange_operating_mic: "AMFI")
    assert_equal [ 25 ], Trade.where(security: bluechip).map { |t| t.qty.to_i }
    assert_equal [ -10 ], Trade.where(security: flexi).map { |t| t.qty.to_i }
    assert_equal [ "12345678/90" ], Trade.where(security: [ bluechip, flexi ]).map(&:folio_number).uniq
    assert_equal BigDecimal("5000"), Trade.find_by!(qty: 25).entry.amount
    assert_equal(-BigDecimal("2100"), Trade.find_by!(qty: -10).entry.amount)

    unknown = Security.find_by!(isin: "INF999Z01ZZ9")
    assert unknown.offline?
    assert_equal 40, Trade.find_by!(security: unknown).qty
  end

  test "mutual fund template is idempotent" do
    build_import("mf_template.csv", preset: "mf_template").publish

    again = build_import("mf_template.csv", preset: "mf_template")

    assert_equal 0, again.dry_run[:transactions]
    assert_equal 3, again.dry_run[:already_imported]
  end

  test "rows with an unknown buy sell value are invalid so the user can fix them" do
    import = build_import("zerodha_tradebook.csv")
    row = import.rows.first
    row.update_columns(qty: "")

    assert row.reload.invalid?
  end

  test "csv template comes from the preset" do
    import = @family.imports.create!(type: "BrokerTradebookImport", broker_preset: "mf_template")

    assert_equal [ "date", "scheme_code or isin", "folio", "units", "nav", "amount", "type" ], import.csv_template.headers
  end

  test "presets are listed in the config file" do
    assert_equal %w[zerodha_console mf_template generic_broker], Import::BrokerPreset.all.map(&:key)
    assert Import::BrokerPreset.find("generic_broker").unverified?
    assert_not Import::BrokerPreset.find("zerodha_console").unverified?
    assert_equal "generic_broker", Import::BrokerPreset.detect([ "Scrip Name", "Trade Date", "Buy/Sell", "Qty", "Rate" ]).key
  end
end
