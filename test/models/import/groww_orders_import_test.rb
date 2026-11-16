require "test_helper"
require "support/mutual_fund_scheme_test_helper"
require "support/xlsx_test_helper"

# Groww mutual fund order history: preset detection, blank rows, date text, matching by fund name
class Import::GrowwOrdersImportTest < ActiveSupport::TestCase
  include MutualFundSchemeTestHelper
  include XlsxTestHelper

  HEADERS = [ "Scheme Name", "Transaction Type", "Units", "NAV", "Amount", "Date" ].freeze
  ORDERS = [
    [ "Sigma Alpha Index Fund Direct Growth", "REDEEM", "10.5", "180", "1,890", "15 Nov 2025" ],
    [ "Sigma Alpha Index Fund Direct Growth", "PURCHASE", "50.00", "120.00", "6,000", "10 Jan 2025" ],
    [ "Sigma Midcap Fund Direct Growth", "PURCHASE", "3.2", "310.55", "1,00,000", "02 Jan 2025" ],
    [ "Zeta Mystery Fund Direct Growth", "PURCHASE", "5", "100", "500", "03 Feb 2025" ]
  ].freeze

  setup do
    @schemes = create_sigma_schemes
    @family = families(:dylan_family)
    @account = @family.accounts.create!(name: "Groww", balance: 0, currency: "INR", accountable: Investment.new, subtype: "mutual_fund")
  end

  def upload_csv(import, csv)
    import.update!(raw_file_str: import.prepare_raw_csv(csv), account: @account)
    import.update!(date_format: import.preset.date_format, number_format: "1,234.56")
    import.generate_rows_from_csv
    import.reload.sync_mappings
    import.reload
  end

  def orders_csv(orders = ORDERS)
    xlsx = groww_orders_xlsx(orders)
    Import::XlsxReader.to_csv(xlsx)
  end

  def build_import(orders = ORDERS)
    upload_csv(@family.imports.create!(type: "BrokerTradebookImport"), orders_csv(orders))
  end

  test "the Groww headers select the Groww preset" do
    assert_equal "groww_mf_orders", Import::BrokerPreset.detect(HEADERS).key
    assert_not Import::BrokerPreset.find("groww_mf_orders").unverified?
    assert_equal "groww_mf_orders", @family.imports.create!(type: "BrokerTradebookImport", raw_file_str: orders_csv).tap { |i| i.update!(raw_file_str: i.prepare_raw_csv(i.raw_file_str)) }.preset.key
  end

  test "blank lines under the header do not become rows and dates stay whole" do
    import = build_import

    assert_equal 4, import.rows.count
    assert_equal [ "02 Jan 2025", "10 Jan 2025", "03 Feb 2025", "15 Nov 2025" ], import.rows.map(&:date).sort_by { |date| Date.strptime(date, "%d %b %Y") }
    assert import.rows.all?(&:valid?)
  end

  test "units, nav and amounts are read with the right signs" do
    rows = build_import.rows.index_by(&:date)

    assert_equal [ "-10.5", "180.0", "-1890.0" ], rows["15 Nov 2025"].values_at(:qty, :price, :amount)
    assert_equal [ "50.0", "120.0", "6000.0" ], rows["10 Jan 2025"].values_at(:qty, :price, :amount)
    assert_equal "100000.0", rows["02 Jan 2025"].amount
  end

  test "funds are matched by name and unresolved ones wait for the user" do
    import = build_import
    mappings = import.mappings.schemes.index_by(&:key)

    assert_equal [ Import::AccountMapping, Import::SchemeMapping ].last, import.mapping_steps.last
    assert_equal @schemes[:nifty_direct], mappings["Sigma Alpha Index Fund Direct Growth"].mappable
    assert_equal @schemes[:midcap_direct], mappings["Sigma Midcap Fund Direct Growth"].mappable
    assert_nil mappings["Zeta Mystery Fund Direct Growth"].mappable

    assert import.cleaned?
    assert_not import.publishable?
  end

  test "a fund the user maps is kept when mappings are synced again" do
    import = build_import
    mapping = import.mappings.schemes.find_by!(key: "Zeta Mystery Fund Direct Growth")
    mapping.update!(mappable: @schemes[:nifty_regular])

    import.sync_mappings

    assert_equal @schemes[:nifty_regular], mapping.reload.mappable
    assert import.reload.publishable?
  end

  test "publishing creates trades on the scheme securities and re-importing creates no duplicates" do
    import = build_import
    import.mappings.schemes.find_by!(key: "Zeta Mystery Fund Direct Growth").update!(mappable: @schemes[:nifty_regular])

    assert_difference -> { Trade.count } => 4 do
      import.publish
    end
    assert_equal "complete", import.reload.status

    nifty = Security.find_by!(ticker: "400001", exchange_operating_mic: "AMFI")
    assert_equal "mutual_fund", nifty.kind
    trades = Trade.joins(:entry).where(security: nifty).order("entries.date")
    assert_equal [ BigDecimal("50"), BigDecimal("-10.5") ], trades.map(&:qty)
    assert_equal [ BigDecimal("120"), BigDecimal("180") ], trades.map(&:price)
    assert_equal [ BigDecimal("6000"), BigDecimal("-1890") ], trades.map { |trade| trade.entry.amount }
    assert_equal [ nil ], trades.map(&:folio_number).uniq
    assert_equal Date.new(2025, 1, 10), trades.first.entry.date

    again = build_import
    again.mappings.schemes.find_by!(key: "Zeta Mystery Fund Direct Growth").update!(mappable: @schemes[:nifty_regular])
    assert_equal({ transactions: 0, already_imported: 4 }, again.dry_run)

    assert_no_difference -> { Trade.count } do
      again.publish
    end
  end

  test "date text keeps month names and drops only a time of day" do
    preset = Import::BrokerPreset.find("groww_mf_orders")
    {
      "10 Jan 2025" => "10 Jan 2025",
      "10-Jan-2025" => "10-Jan-2025",
      "10 Jan 25" => "10 Jan 25",
      "2024-01-15T09:32:11" => "2024-01-15",
      "2024-01-15 09:32:11" => "2024-01-15",
      "15-01-2024 09:32" => "15-01-2024",
      "15-01-2024 9:32 PM" => "15-01-2024",
      "2024-01-15T09:32:11+05:30" => "2024-01-15"
    }.each do |input, expected|
      assert_equal expected, preset.send(:date_text, input), input
    end
  end

  test "fully blank lines are skipped for other presets too" do
    csv = "date,scheme_code or isin,folio,units,nav,amount,type\n\n,,,,,,\n15-01-2024,100001,12345678/90,25.000,200.00,5000.00,buy\n"
    import = @family.imports.create!(type: "BrokerTradebookImport", account: @account, broker_preset: "mf_template", raw_file_str: csv)
    import.update!(date_format: "%d-%m-%Y")
    import.generate_rows_from_csv

    assert_equal 1, import.rows.count
  end
end
