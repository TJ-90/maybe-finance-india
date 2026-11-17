require "test_helper"
require "support/xlsx_test_helper"

class Import::UploadsControllerTest < ActionDispatch::IntegrationTest
  include XlsxTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @import = imports(:transaction)
  end

  test "show" do
    get import_upload_url(@import)
    assert_response :success
  end

  test "uploads valid csv by copy and pasting" do
    patch import_upload_url(@import), params: {
      import: {
        raw_file_str: file_fixture("imports/valid.csv").read,
        col_sep: ","
      }
    }

    assert_redirected_to import_configuration_url(@import, template_hint: true)
    assert_equal "CSV uploaded successfully.", flash[:notice]
  end

  test "uploads valid csv by file" do
    patch import_upload_url(@import), params: {
      import: {
        csv_file: file_fixture_upload("imports/valid.csv"),
        col_sep: ","
      }
    }

    assert_redirected_to import_configuration_url(@import, template_hint: true)
    assert_equal "CSV uploaded successfully.", flash[:notice]
  end

  test "uploading a bank statement with account details above the header strips them" do
    patch import_upload_url(@import), params: {
      import: {
        csv_file: file_fixture_upload("imports/india/sbi_savings.csv"),
        col_sep: ","
      }
    }

    assert_redirected_to import_configuration_url(@import, template_hint: true)
    assert_equal [ "Txn Date", "Value Date", "Description", "Ref No./Cheque No.", "Debit", "Credit", "Balance" ], @import.reload.csv_headers
  end

  test "invalid csv cannot be uploaded" do
    patch import_upload_url(@import), params: {
      import: {
        csv_file: file_fixture_upload("imports/invalid.csv"),
        col_sep: ","
      }
    }

    assert_response :unprocessable_entity
    assert_equal "Must be valid CSV with headers and at least one row of data", flash[:alert]
  end

  test "uploads a Groww Excel workbook, strips the preamble and detects the preset" do
    import = @user.family.imports.create!(type: "BrokerTradebookImport")
    xlsx = groww_orders_xlsx([ [ "Sigma Alpha Index Fund Direct Growth", "PURCHASE", "50.00", "120.00", "6,000", "10 Jan 2025" ] ])

    patch import_upload_url(import), params: { import: { csv_file: xlsx_upload(xlsx), col_sep: ";" } }

    assert_redirected_to import_configuration_url(import, template_hint: true)
    import.reload
    assert_equal ",", import.col_sep
    assert_equal [ "Scheme Name", "Transaction Type", "Units", "NAV", "Amount", "Date" ], import.csv_headers
    assert_equal "groww_mf_orders", import.preset.key
  end

  test "uploads an Excel workbook to a plain trade import" do
    import = @user.family.imports.create!(type: "TradeImport")
    xlsx = build_xlsx([ [ "date", "ticker", "qty", "price" ], [ "01/02/2025", "INFY", 5, 1500.5 ] ])

    patch import_upload_url(import), params: { import: { csv_file: xlsx_upload(xlsx), col_sep: "," } }

    assert_redirected_to import_configuration_url(import, template_hint: true)
    assert_equal [ "date", "ticker", "qty", "price" ], import.reload.csv_headers
    assert_equal "Excel file uploaded successfully.", flash[:notice]
  end

  test "an old binary xls file is refused with advice" do
    xls = "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b + ("\x00" * 200)

    patch import_upload_url(@import), params: { import: { csv_file: xlsx_upload(xls, filename: "old.xls"), col_sep: "," } }

    assert_response :unprocessable_entity
    assert_match "save it as .xlsx or CSV", flash[:alert]
    assert_not @import.reload.uploaded?
  end

  test "a zip that is not a workbook is refused" do
    patch import_upload_url(@import), params: { import: { csv_file: xlsx_upload(zip_entries("a.txt" => "x"), filename: "x.xlsx"), col_sep: "," } }

    assert_response :unprocessable_entity
    assert_match "not an Excel workbook", flash[:alert]
  end

  test "upload page accepts Excel files" do
    get import_upload_url(@import)

    assert_select "input[type=file][accept*='.xlsx']"
    assert_match "Excel (.xlsx)", response.body
  end
end
