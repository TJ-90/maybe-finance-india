require "test_helper"
require "support/pdf_test_helper"

class CasImport::PdfTextTest < ActiveSupport::TestCase
  include PdfTestHelper

  LINES = [
    "Folio No: 123/45   PAN: ABCDE1234F",
    "01-Jan-2024 Purchase 5,000.00 50.123 99.75 50.123",
    "Closing Unit Balance: 50.123"
  ].freeze

  test "extracts text from an unprotected PDF" do
    text = CasImport::PdfText.extract(build_pdf(LINES))

    assert_includes text, "Folio No: 123/45"
    assert_includes text, "01-Jan-2024 Purchase 5,000.00 50.123 99.75 50.123"
  end

  test "extracts text from an IO" do
    text = CasImport::PdfText.extract(StringIO.new(build_pdf(LINES)))

    assert_includes text, "Closing Unit Balance: 50.123"
  end

  test "decrypts a password protected PDF" do
    pdf = build_pdf(LINES, password: "ABCDE1234F")

    text = CasImport::PdfText.extract(pdf, password: "ABCDE1234F")

    assert_includes text, "Closing Unit Balance: 50.123"
  end

  test "asks for a password when the PDF is locked" do
    pdf = build_pdf(LINES, password: "ABCDE1234F")

    assert_raises(CasImport::PdfText::PasswordRequiredError) { CasImport::PdfText.extract(pdf) }
  end

  test "rejects a wrong password" do
    pdf = build_pdf(LINES, password: "ABCDE1234F")

    assert_raises(CasImport::PdfText::InvalidPasswordError) { CasImport::PdfText.extract(pdf, password: "nope") }
  end

  test "rejects files that are not PDFs" do
    assert_raises(CasImport::PdfText::UnreadablePdfError) { CasImport::PdfText.extract("just text") }
  end

  test "falls back to a clear error when pdf-reader cannot read it and qpdf is missing" do
    PDF::Reader.stubs(:new).raises(PDF::Reader::UnsupportedFeatureError)
    CasImport::PdfText.stubs(:qpdf_available?).returns(false)

    error = assert_raises(CasImport::PdfText::UnsupportedEncryptionError) { CasImport::PdfText.extract(build_pdf(LINES)) }
    assert_match(/unlocked copy/, error.message)
  end

  test "uses qpdf when pdf-reader cannot read the file" do
    unlocked = build_pdf(LINES)
    PDF::Reader.stubs(:new).raises(PDF::Reader::UnsupportedFeatureError).then.returns(PDF::Reader.allocate.tap do |reader|
      reader.stubs(:pages).returns([ stub(text: "decrypted by qpdf") ])
    end)
    CasImport::PdfText.stubs(:qpdf_available?).returns(true)
    Open3.stubs(:capture3).with { |*args| File.binwrite(args.last, unlocked) || true }.returns([ "", "", stub(success?: true, exitstatus: 0) ])

    assert_equal "decrypted by qpdf", CasImport::PdfText.extract(unlocked, password: "x")
  end
end
