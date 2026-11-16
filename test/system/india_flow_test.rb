require "application_system_test_case"

# The critical India flow: import a mutual fund statement (CAS), see the holdings with XIRR, then
# open the Tax Center. The PDF text extraction is stubbed with a synthetic statement, so no real PDF
# parsing or network access is involved.
class IndiaFlowTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:family_admin)
    @user.family.update!(currency: "INR", country: "IN", date_format: "%d-%m-%Y", timezone: "Asia/Kolkata")
    @user.family.imports.destroy_all

    # Funds unknown to AMFI data become offline securities valued at their trade prices
    Security.stubs(:provider).returns(nil)
    CasImport::PdfText.stubs(:extract).returns(file_fixture("cas/cams_detailed.txt").read)

    sign_in @user
  end

  test "import a CAS, see holdings with XIRR, open the Tax Center" do
    visit new_import_path
    click_on "Mutual fund CAS (PDF)"

    assert_text "Import a mutual fund statement"
    attach_file "import[pdf_file]", placeholder_pdf.path, make_visible: true # the text comes from the stub above
    click_on "Read statement"

    assert_text "Your data has been cleaned"
    click_on "Next step"

    assert_selector "h1", text: "Assign your accounts"
    click_on "Next"

    assert_text "new,"
    click_on "Publish import"

    assert_text "Import in progress"
    perform_enqueued_jobs(only: ImportJob)
    click_on "Check status"
    assert_text "Import successful"

    account = @user.family.accounts.find_by!(name: "Mutual Funds – Asha")
    Sync.create!(syncable: account).perform # what the account sync job that follows the import does
    visit account_path(account)

    assert_text "Orchid Flexi Cap Fund"
    assert_selector "#account-investment-summary", text: "XIRR"
    assert_selector "#account-investment-summary div", text: /XIRR\s*-?[\d.,]+%/

    click_link "Tax"

    assert_selector "h1", text: "Tax Center"
    assert_text "Indicative estimates only"
    assert_text "Financial year"
  end

  private
    def placeholder_pdf
      Tempfile.new([ "cas", ".pdf" ]).tap do |file|
        file.write("%PDF-1.4 synthetic placeholder")
        file.close
      end
    end
end
