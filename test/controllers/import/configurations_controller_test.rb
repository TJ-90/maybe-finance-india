require "test_helper"

class Import::ConfigurationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @import = imports(:transaction)
  end

  test "show" do
    get import_configuration_url(@import)
    assert_response :success
  end

  test "show pre-fills the form from a bank preset without saving" do
    @import.update!(raw_file_str: file_fixture("imports/india/hdfc_savings.csv").read)

    get import_configuration_url(@import, statement: { preset: "hdfc_savings" })

    assert_response :success
    assert_select "select[name='import[debit_col_label]'] option[selected][value='Withdrawal Amt.']"
    assert_select "select[name='import[credit_col_label]'] option[selected][value='Deposit Amt.']"
    assert_select "select[name='import[amount_type_strategy]'] option[selected][value='debit_credit_columns']"
    assert_nil @import.reload.debit_col_label
  end

  test "show warns when the preset is unverified" do
    @import.update!(raw_file_str: file_fixture("imports/india/axis_savings.csv").read)

    get import_configuration_url(@import, statement: { preset: "axis_savings" })

    assert_response :success
    assert_match "best guess", response.body
  end

  test "updating saves debit and credit column labels" do
    patch import_configuration_url(@import), params: {
      import: {
        date_col_label: "Date", date_format: "%d/%m/%y", name_col_label: "Narration",
        amount_type_strategy: "debit_credit_columns",
        debit_col_label: "Withdrawal Amt.", credit_col_label: "Deposit Amt.",
        number_format: "1,234.56"
      }
    }

    assert_redirected_to import_clean_url(@import)
    @import.reload
    assert_equal "debit_credit_columns", @import.amount_type_strategy
    assert_equal "Withdrawal Amt.", @import.debit_col_label
    assert_equal "Deposit Amt.", @import.credit_col_label
  end

  test "updating a valid configuration regenerates rows" do
    TransactionImport.any_instance.expects(:generate_rows_from_csv).once

    patch import_configuration_url(@import), params: {
      import: {
        date_col_label: "Date",
        date_format: "%Y-%m-%d",
        name_col_label: "Name",
        category_col_label: "Category",
        tags_col_label: "Tags",
        amount_col_label: "Amount",
        signage_convention: "inflows_positive",
        account_col_label: "Account",
        number_format: "1.234,56"
      }
    }

    assert_redirected_to import_clean_url(@import)
    assert_equal "Import configured successfully.", flash[:notice]

    # Verify configurations were saved
    @import.reload
    assert_equal "Date", @import.date_col_label
    assert_equal "%Y-%m-%d", @import.date_format
    assert_equal "Name", @import.name_col_label
    assert_equal "Category", @import.category_col_label
    assert_equal "Tags", @import.tags_col_label
    assert_equal "Amount", @import.amount_col_label
    assert_equal "inflows_positive", @import.signage_convention
    assert_equal "Account", @import.account_col_label
    assert_equal "1.234,56", @import.number_format
  end
end
