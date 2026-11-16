require "test_helper"

class Import::StatementPresetTest < ActiveSupport::TestCase
  FIXTURE_DIR = Rails.root.join("test", "fixtures", "files", "imports", "india")

  SAVINGS_AMOUNTS = [ 450, -125000.50, 5000, -312.75 ].map { |n| BigDecimal(n.to_s) }
  CARD_AMOUNTS = [ 450, -25000, 1299.50, -100 ].map { |n| BigDecimal(n.to_s) }

  # preset key => [fixture file, expected signed amounts]
  FIXTURES = {
    "hdfc_savings" => [ "hdfc_savings.csv", SAVINGS_AMOUNTS ],
    "icici_savings" => [ "icici_savings.csv", SAVINGS_AMOUNTS ],
    "sbi_savings" => [ "sbi_savings.csv", SAVINGS_AMOUNTS ],
    "axis_savings" => [ "axis_savings.csv", SAVINGS_AMOUNTS ],
    "kotak_savings" => [ "kotak_savings.csv", SAVINGS_AMOUNTS ],
    "idfc_first_savings" => [ "idfc_first_savings.csv", SAVINGS_AMOUNTS ],
    "yes_savings" => [ "yes_savings.csv", SAVINGS_AMOUNTS ],
    "generic" => [ "generic_statement.csv", SAVINGS_AMOUNTS ],
    "hdfc_credit_card" => [ "hdfc_credit_card.csv", CARD_AMOUNTS ],
    "icici_credit_card" => [ "icici_credit_card.csv", CARD_AMOUNTS ],
    "sbi_card" => [ "sbi_card.csv", CARD_AMOUNTS ],
    "axis_credit_card" => [ "axis_credit_card.csv", CARD_AMOUNTS ]
  }.freeze

  test "every preset in the YAML has a fixture test" do
    assert_equal Import::StatementPreset.all.map(&:key).sort, FIXTURES.keys.sort
  end

  test "presets are grouped for the select" do
    groups = Import::StatementPreset.grouped_options.map(&:first)

    assert_equal [ "Bank accounts", "Credit cards", "Other" ], groups
  end

  test "only HDFC and SBI headers are marked confirmed" do
    confirmed = Import::StatementPreset.all.reject(&:unverified?).map(&:key)

    assert_equal %w[hdfc_savings sbi_savings], confirmed.sort
  end

  FIXTURES.each do |key, (file, expected_amounts)|
    test "#{key} preset imports its fixture with correct signs and amounts" do
      import = imports(:transaction)
      raw = Import.strip_preamble(File.read(FIXTURE_DIR.join(file)))
      import.update!(raw_file_str: raw, account: accounts(:depository))

      preset = Import::StatementPreset.find(key)
      import.update!(preset.attributes_for(import))
      import.generate_rows_from_csv
      import.reload

      assert_equal 4, import.rows.count, "skipped or kept the wrong lines"
      assert import.rows.all?(&:valid?), import.rows.reject(&:valid?).map { |r| r.errors.full_messages }.inspect

      amounts = import.rows.sort_by(&:date_iso).map(&:signed_amount)
      assert_equal expected_amounts, amounts
    end
  end

  test "attributes_for only returns roles that matched a header" do
    import = imports(:transaction)
    import.update!(raw_file_str: "Foo,Bar,Baz\n1,2,3")

    attrs = Import::StatementPreset.find("hdfc_savings").attributes_for(import)

    assert_nil attrs[:date_col_label]
    assert_nil attrs[:debit_col_label]
    assert_equal "debit_credit_columns", attrs[:amount_type_strategy]
    assert_equal "%d/%m/%y", attrs[:date_format]
  end

  test "card preset resolves the inflow indicator to the casing used in the file" do
    import = imports(:transaction)
    import.update!(raw_file_str: File.read(FIXTURE_DIR.join("icici_credit_card.csv")))
    import.update!(raw_file_str: Import.strip_preamble(import.raw_file_str))

    attrs = Import::StatementPreset.find("icici_credit_card").attributes_for(import)

    assert_equal "CR", attrs[:amount_type_inflow_value]
    assert_equal "BillingAmountSign", attrs[:entity_type_col_label]
  end

  test "unknown preset key returns nil" do
    assert_nil Import::StatementPreset.find("nope")
  end
end
