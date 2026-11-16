require "test_helper"

class Import::UploadsControllerTest < ActionDispatch::IntegrationTest
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
end
