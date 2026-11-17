require "test_helper"

class ImportPreambleTest < ActiveSupport::TestCase
  test "leaves a normal csv untouched" do
    csv = "Date,Name,Amount\n2024-01-01,Coffee,-4.50\n"

    assert_equal csv, Import.strip_preamble(csv)
  end

  test "leaves a two column csv untouched" do
    csv = "date,amount\n2024-01-01,5\n"

    assert_equal csv, Import.strip_preamble(csv)
  end

  test "drops account details above the header row" do
    csv = <<~CSV
      Account Name :,TEST USER,,
      Account Number :,0000123,,

      Txn Date,Description,Debit,Credit
      01/04/2024,Rent,100.00,
    CSV

    cleaned = Import.strip_preamble(csv)

    assert_equal [ "Txn Date", "Description", "Debit", "Credit" ], Import.parse_csv_str(cleaned).headers
    assert_equal 1, Import.parse_csv_str(cleaned).count
  end

  test "removes a UTF-8 byte order mark" do
    csv = "\uFEFFDate,Name,Amount\n2024-01-01,Coffee,4\n"

    assert_equal "Date,Name,Amount\n2024-01-01,Coffee,4\n", Import.strip_preamble(csv)
  end

  test "handles binary-encoded uploads" do
    csv = "Preamble line\nDate,Narration,Debit,Credit\n01/04/2024,Rent,1.00,\n".b

    assert_equal [ "Date", "Narration", "Debit", "Credit" ], Import.parse_csv_str(Import.strip_preamble(csv)).headers
  end

  test "supports semicolon separated files" do
    csv = "Statement;;\nDate;Narration;Debit;Credit\n01/04/2024;Rent;1,00;\n"

    cleaned = Import.strip_preamble(csv, col_sep: ";")

    assert_equal [ "Date", "Narration", "Debit", "Credit" ], Import.parse_csv_str(cleaned, col_sep: ";").headers
  end

  test "the configuration sample skips blank rows under the header" do
    import = Import.new(raw_file_str: "Scheme,Units,Amount\n,,\n,,\nSigma Fund,10,1000\nOmega Fund,5,500\nThird Fund,1,100\n", col_sep: ",")

    assert_equal [ [ "Sigma Fund", "10", "1000" ], [ "Omega Fund", "5", "500" ] ], import.csv_sample.map(&:fields)
  end
end
