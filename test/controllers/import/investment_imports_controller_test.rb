require "test_helper"
require "support/pdf_test_helper"

class Import::InvestmentImportsControllerTest < ActionDispatch::IntegrationTest
  include PdfTestHelper

  PDF_LINES = [
    "As on 31-Mar-2024",
    "Name: ASHA KUMAR",
    "PAN: ABCDE1234F",
    "Orchid Mutual Fund",
    "12345678/90 INF000A01AB1 Orchid Flexi Cap Fund 25,000.00 120.960 31-Mar-2024 300.00 36,288.00"
  ].freeze

  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
  end

  test "new import page offers the CAS and broker options" do
    get new_import_url

    assert_response :success
    assert_select "button", text: /Mutual fund CAS \(PDF\)/
    assert_select "button", text: /Broker tradebook/
    assert_select "button", text: /Mutual fund transactions \(CSV template\)/
  end

  test "creates a CAS import and shows the PDF upload form" do
    assert_difference -> { CasImport.count }, 1 do
      post imports_url, params: { import: { type: "CasImport" } }
    end

    import = CasImport.order(:created_at).last
    assert_redirected_to import_upload_url(import)

    get import_upload_url(import)
    assert_response :success
    assert_select "input[type=file][name='import[pdf_file]']"
    assert_select "input[type=password][name='import[pdf_password]']"
  end

  test "uploading a password protected CAS reads it and moves to the clean step" do
    import = @family.imports.create!(type: "CasImport")
    pdf = build_pdf(PDF_LINES, password: "ABCDE1234F")

    patch import_upload_url(import), params: {
      import: { pdf_file: pdf_upload(pdf), pdf_password: "ABCDE1234F" }
    }

    assert_redirected_to import_clean_url(import)
    assert_equal 1, import.reload.rows.count
    assert_nil import.raw_file_str[/ABCDE1234F/]
  end

  test "wrong or missing PDF password re-renders with a message" do
    import = @family.imports.create!(type: "CasImport")
    pdf = build_pdf(PDF_LINES, password: "ABCDE1234F")

    patch import_upload_url(import), params: { import: { pdf_file: pdf_upload(pdf), pdf_password: "wrong" } }

    assert_response :unprocessable_entity
    assert_equal "That password did not unlock the PDF. Check it and try again.", flash[:alert]
    assert_equal 0, import.reload.rows.count
  end

  test "CAS imports skip the configuration step" do
    import = @family.imports.create!(type: "CasImport")

    get import_configuration_url(import)

    assert_redirected_to import_clean_url(import)
  end

  test "confirm step shows new and already imported counts" do
    import = @family.imports.create!(type: "CasImport")
    import.load_text!(file_fixture("cas/summary.txt").read)

    get import_confirm_url(import)
    assert_response :success

    get import_url(import)
    assert_response :success
    assert_select "p", text: /2 new, 0 already imported/
    assert_select "span", text: "XXXXX1234X"
  end

  test "broker import configuration pre-selects the detected format" do
    import = @family.imports.create!(type: "BrokerTradebookImport")
    patch import_upload_url(import), params: { import: { csv_file: file_fixture_upload("imports/india/zerodha_tradebook.csv"), col_sep: "," } }

    get import_configuration_url(import)

    assert_response :success
    assert_select "option[selected][value=zerodha_console]"
  end

  test "creating the MF template import preselects its preset" do
    post imports_url, params: { import: { type: "BrokerTradebookImport", broker_preset: "mf_template" } }

    assert_equal "mf_template", BrokerTradebookImport.order(:created_at).last.broker_preset
  end

  private
    def pdf_upload(bytes)
      file = Tempfile.new([ "cas", ".pdf" ], binmode: true)
      file.write(bytes)
      file.rewind
      Rack::Test::UploadedFile.new(file.path, "application/pdf", true)
    end
end
