require "test_helper"

class TransactionImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper, ImportInterfaceTest

  setup do
    @subject = @import = imports(:transaction)
  end

  test "uploaded? if raw_file_str is present" do
    @import.expects(:raw_file_str).returns("test").once
    assert @import.uploaded?
  end

  test "configured? if uploaded and rows are generated" do
    @import.expects(:uploaded?).returns(true).once
    assert @import.configured?
  end

  test "cleaned? if rows are generated and valid" do
    @import.expects(:configured?).returns(true).once
    assert @import.cleaned?
  end

  test "publishable? if cleaned and mappings are valid" do
    @import.expects(:cleaned?).returns(true).once
    assert @import.publishable?
  end

  test "imports transactions, categories, tags, and accounts" do
    import = <<~CSV
      date,name,amount,category,tags,account,notes
      01/01/2024,Txn1,100,TestCategory1,TestTag1,TestAccount1,notes1
      01/02/2024,Txn2,200,TestCategory2,TestTag1|TestTag2,TestAccount2,notes2
      01/03/2024,Txn3,300,,,,notes3
    CSV

    @import.update!(
      raw_file_str: import,
      date_col_label: "date",
      amount_col_label: "amount",
      date_format: "%m/%d/%Y"
    )

    @import.generate_rows_from_csv

    @import.mappings.create! key: "TestCategory1", create_when_empty: true, type: "Import::CategoryMapping"
    @import.mappings.create! key: "TestCategory2", mappable: categories(:food_and_drink), type: "Import::CategoryMapping"
    @import.mappings.create! key: "", create_when_empty: false, mappable: nil, type: "Import::CategoryMapping" # Leaves uncategorized

    @import.mappings.create! key: "TestTag1", create_when_empty: true, type: "Import::TagMapping"
    @import.mappings.create! key: "TestTag2", mappable: tags(:one), type: "Import::TagMapping"
    @import.mappings.create! key: "", create_when_empty: false, mappable: nil, type: "Import::TagMapping" # Leaves untagged

    @import.mappings.create! key: "TestAccount1", create_when_empty: true, type: "Import::AccountMapping"
    @import.mappings.create! key: "TestAccount2", mappable: accounts(:depository), type: "Import::AccountMapping"
    @import.mappings.create! key: "", mappable: accounts(:depository), type: "Import::AccountMapping"

    @import.reload

    assert_difference -> { Entry.count } => 3,
                      -> { Transaction.count } => 3,
                      -> { Tag.count } => 1,
                      -> { Category.count } => 1,
                      -> { Account.count } => 1 do
      @import.publish
    end

    assert_equal "complete", @import.status
  end

  test "imports transactions with separate type column for signage convention" do
    import = <<~CSV
      date,amount,amount_type
      01/01/2024,100,debit
      01/02/2024,200,credit
      01/03/2024,300,debit
    CSV

    @import.update!(
      account: accounts(:depository),
      raw_file_str: import,
      date_col_label: "date",
      date_format: "%m/%d/%Y",
      amount_col_label: "amount",
      entity_type_col_label: "amount_type",
      amount_type_inflow_value: "debit",
      amount_type_strategy: "custom_column",
      signage_convention: nil # Explicitly set to nil to prove this is not needed
    )

    @import.generate_rows_from_csv

    @import.reload

    assert_difference -> { Entry.count } => 3,
                      -> { Transaction.count } => 3 do
      @import.publish
    end

    assert_equal [ -100, 200, -300 ], @import.entries.map(&:amount)
  end

  test "imports a debit/credit column statement with parsed narrations, merchants and category hints" do
    family = @import.family
    food = family.categories.create!(name: "Food Delivery & Dining", color: "#eb5429", lucide_icon: "utensils", classification: "expense")
    invest = family.categories.create!(name: "Investments & SIP", color: "#4da568", lucide_icon: "trending-up", classification: "expense")
    interest = family.categories.create!(name: "Interest", color: "#e99537", lucide_icon: "percent", classification: "income")

    configure_statement_import("hdfc_savings")

    assert_difference -> { Entry.count } => 4, -> { Transaction.count } => 4, -> { FamilyMerchant.count } => 3 do
      @import.publish
    end

    assert_equal "complete", @import.status

    entries = @import.entries.includes(:entryable).index_by(&:name)
    assert_equal [ "Acme Pvt Ltd", "BSE Limited", "Interest credit", "Swiggy" ], entries.keys.sort

    swiggy = entries["Swiggy"]
    assert_equal 450, swiggy.amount
    assert_equal "upi", swiggy.transaction.payment_mode
    assert_equal "412345678901", swiggy.transaction.reference_number
    assert_equal "Swiggy", swiggy.transaction.merchant.name
    assert_equal food, swiggy.transaction.category
    assert_includes swiggy.notes, "UPI-SWIGGY-swiggy@icici"
    assert_equal "import_hint", DataEnrichment.find_by!(enrichable: swiggy.transaction, attribute_name: "category_id").source

    salary = entries["Acme Pvt Ltd"]
    assert_equal(-125000.50, salary.amount)
    assert_equal "neft", salary.transaction.payment_mode
    assert_nil salary.transaction.category # no hint for this counterparty

    sip = entries["BSE Limited"]
    assert_equal "nach", sip.transaction.payment_mode
    assert_equal invest, sip.transaction.category
    assert_equal "BSE Limited", sip.transaction.merchant.name

    assert_equal "other", entries["Interest credit"].transaction.payment_mode
    assert_equal interest, entries["Interest credit"].transaction.category
    assert_nil entries["Interest credit"].transaction.merchant
  end

  test "category hints never override a category supplied by the file" do
    family = @import.family
    family.categories.create!(name: "Food Delivery & Dining", color: "#eb5429", lucide_icon: "utensils", classification: "expense")

    @import.update!(
      raw_file_str: "date,name,amount,category\n01/01/2024,UPI-SWIGGY-swiggy@icici-ICIC0000001-412345678901-UPI,100,Treats\n",
      account: accounts(:depository),
      date_col_label: "date", name_col_label: "name", amount_col_label: "amount",
      category_col_label: "category", date_format: "%m/%d/%Y"
    )
    @import.generate_rows_from_csv
    @import.reload.sync_mappings

    @import.publish

    transaction = @import.entries.first.transaction
    assert_equal "Treats", transaction.category.name
    assert_equal "Swiggy", transaction.merchant.name
  end

  test "hints are skipped when the family has no matching category" do
    configure_statement_import("hdfc_savings")

    assert_no_difference -> { Category.count } do
      @import.publish
    end

    assert @import.entries.map { |e| e.transaction.category }.all?(&:nil?)
  end

  test "reuses an existing merchant instead of creating a duplicate" do
    existing = @import.family.merchants.create!(name: "Swiggy")
    configure_statement_import("hdfc_savings")

    @import.publish

    swiggy_entry = @import.entries.find_by(name: "Swiggy")
    assert_equal existing, swiggy_entry.transaction.merchant
    assert_equal 1, @import.family.merchants.where("LOWER(name) = 'swiggy'").count
  end

  test "unrecognised narrations keep their original name" do
    @import.update!(
      raw_file_str: "date,name,amount\n01/01/2024,Grocery Store,25\n",
      account: accounts(:depository),
      date_col_label: "date", name_col_label: "name", amount_col_label: "amount", date_format: "%m/%d/%Y"
    )
    @import.generate_rows_from_csv
    @import.reload.sync_mappings

    assert_no_difference -> { FamilyMerchant.count } do
      @import.publish
    end

    transaction = @import.entries.first.transaction
    assert_equal "Grocery Store", @import.entries.first.name
    assert_nil transaction.payment_mode
    assert_nil @import.entries.first.notes
  end

  test "debit_credit_columns derives signed amounts and skips non-data lines" do
    csv = <<~CSV
      Date,Narration,Debit,Credit
      01/04/2024,Rent,"12,000.00",
      02/04/2024,Salary,,"1,00,000.00"
      ,,,
      Total,,"12,000.00","1,00,000.00"
    CSV

    @import.update!(
      raw_file_str: csv, date_format: "%d/%m/%Y", date_col_label: "Date", name_col_label: "Narration",
      amount_type_strategy: "debit_credit_columns", debit_col_label: "Debit", credit_col_label: "Credit"
    )
    @import.generate_rows_from_csv

    rows = @import.reload.rows.sort_by(&:date_iso)
    assert_equal [ "-12000", "100000" ], rows.map(&:amount)
    assert_equal [ 12000, -100000 ], rows.map(&:signed_amount)
  end

  private
    def configure_statement_import(preset_key)
      raw = Import.strip_preamble(file_fixture("imports/india/#{preset_key}.csv").read)
      @import.update!(raw_file_str: raw, account: accounts(:depository))
      @import.update!(Import::StatementPreset.find(preset_key).attributes_for(@import))
      @import.generate_rows_from_csv
      @import.reload.sync_mappings
    end
end
