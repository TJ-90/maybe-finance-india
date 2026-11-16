require "test_helper"

class CasImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @family = families(:dylan_family)
    @import = @family.imports.create!(type: "CasImport")
    MutualFundScheme.create!(scheme_code: "555001", name: "Orchid Flexi Cap Fund - Direct Plan - Growth", isin_growth: "INF000A01AB1", isin_reinvestment: "INF000A01AB2")
  end

  def load_fixture(name, import = @import)
    import.load_text!(file_fixture("cas/#{name}.txt").read)
  end

  def publish!(import = @import)
    import.mappings.accounts.each { |mapping| mapping.update!(create_when_empty: true) if mapping.mappable.nil? }
    import.publish
    import.reload
  end

  test "builds rows and an investor account mapping from the statement" do
    load_fixture("cams_detailed")

    assert_equal "INR", @import.rows.first.currency
    assert_equal [ "Mutual Funds – Asha" ], @import.mappings.accounts.pluck(:key)
    assert @import.mappings.accounts.first.create_when_empty
    # IDCW payouts, stamp duty and STT are not trades
    assert_equal 12, @import.rows.count
    assert_equal %w[12345678/90 7000123/45], @import.rows.map(&:folio_number).uniq.sort_by { |f| f == "7000123/45" ? 1 : 0 }
    opening = @import.rows.find_by!(entity_type: "opening_position")
    assert_equal "2023-04-01", opening.date
    assert_equal "100.0", opening.qty
  end

  test "publishing creates trades whose units equal the statement closing units" do
    load_fixture("cams_detailed")

    assert_difference -> { Trade.count } => 12, -> { Account.count } => 1 do
      publish!
    end

    assert_equal "complete", @import.status

    account = @family.accounts.find_by!(name: "Mutual Funds – Asha")
    assert_equal "Investment", account.accountable_type
    assert_equal "mutual_fund", account.subtype

    flexi = Security.find_by!(ticker: "555001", exchange_operating_mic: Security::AMFI_MIC)
    assert_equal "mutual_fund", flexi.kind
    assert_equal BigDecimal("120.96"), account.entries.where(entryable_type: "Trade").map(&:entryable).select { |t| t.security_id == flexi.id }.sum(&:qty)

    liquid = Security.find_by!(isin: "INF000B01CD2")
    assert liquid.offline?
    assert_equal "Lotus Liquid Fund - Direct Plan - Growth", liquid.name

    equity = Security.find_by!(isin: "INF999Z01ZZ9")
    assert_equal BigDecimal("180"), Trade.where(security: equity).sum(:qty)
  end

  test "redemptions and switch outs have negative quantity and trades carry the folio" do
    load_fixture("cams_detailed")
    publish!

    redemption = Trade.joins(:entry).find_by!(qty: -25)
    assert_equal "12345678/90", redemption.folio_number
    assert_equal BigDecimal("250"), redemption.price
    assert_equal(-BigDecimal("6250"), redemption.entry.amount)

    switch_out = Trade.find_by!(qty: -4)
    assert_equal "7000123/45", switch_out.folio_number

    purchase = Trade.find_by!(qty: 20, folio_number: "12345678/90")
    assert_equal BigDecimal("5000"), purchase.entry.amount
  end

  test "importing the same statement again creates no duplicates" do
    load_fixture("cams_detailed")
    publish!

    second = @family.imports.create!(type: "CasImport")
    load_fixture("cams_detailed", second)

    assert_equal({ new_trades: 0, already_imported: 12, accounts: 0 }, second.dry_run)

    assert_no_difference -> { Trade.count } do
      second.publish
    end
    assert_equal "complete", second.reload.status
  end

  test "dry run reports new and already imported counts" do
    load_fixture("cams_detailed")

    assert_equal({ new_trades: 12, already_imported: 0, accounts: 1 }, @import.dry_run)
  end

  test "summary statements import one opening position per scheme at cost" do
    load_fixture("summary")

    assert @import.summary_statement?
    publish!

    account = @family.accounts.find_by!(name: "Mutual Funds – Asha")
    trades = account.entries.where(entryable_type: "Trade").map(&:entryable)
    assert_equal [ BigDecimal("21"), BigDecimal("120.96") ], trades.map(&:qty).sort
    assert_equal BigDecimal("25000"), account.entries.where(date: Date.new(2024, 3, 31)).map(&:amount).max
    assert_match(/no transaction history/, @import.rows.first.notes)
  end

  test "maps onto an existing investment account by name" do
    existing = @family.accounts.create!(name: "Mutual Funds – Asha", balance: 0, currency: "INR", accountable: Investment.new, subtype: "mutual_fund")

    load_fixture("cams_detailed")

    assert_equal existing, @import.mappings.accounts.first.mappable
    assert_no_difference -> { Account.count } do
      @import.publish
    end
  end

  test "only stores masked PANs" do
    load_fixture("cams_detailed")

    refute_includes @import.raw_file_str, "ABCDE1234F"
    assert_includes @import.raw_file_str, "XXXXX1234X"
  end

  test "rejects text with no holdings" do
    assert_raises(CasImport::NoStatementError) { @import.load_text!("nothing here") }
  end

  test "reads a generated PDF without storing it" do
    require "support/pdf_test_helper"
    # Short lines: the generated PDF has a fixed page width
    lines = [
      "As on 31-Mar-2024",
      "Name: ASHA KUMAR",
      "PAN: ABCDE1234F",
      "Orchid Mutual Fund",
      "12345678/90 INF000A01AB1 Orchid Flexi Cap Fund 25,000.00 120.960 31-Mar-2024 300.00 36,288.00",
      "7000123/45 INF000B01CD2 Lotus Liquid Fund 21,000.00 21.000 31-Mar-2024 1,000.00 21,000.00"
    ]
    pdf = PdfTestHelper::PdfBuilder.new(lines, password: "ABCDE1234F").to_s

    @import.load_pdf!(StringIO.new(pdf), password: "ABCDE1234F")

    assert_equal 2, @import.rows.count
    refute_includes @import.raw_file_str, "ABCDE1234F"
  end

  test "publish job receives only the import" do
    load_fixture("summary")
    @import.mappings.accounts.each { |mapping| mapping.update!(create_when_empty: true) }

    assert_enqueued_with job: ImportJob, args: [ @import ] do
      @import.publish_later
    end
  end
end
