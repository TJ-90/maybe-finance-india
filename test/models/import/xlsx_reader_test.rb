require "test_helper"
require "support/xlsx_test_helper"

class Import::XlsxReaderTest < ActiveSupport::TestCase
  include XlsxTestHelper

  def csv_rows(bytes)
    CSV.parse(Import::XlsxReader.to_csv(bytes))
  end

  test "reads shared strings and numbers of the first worksheet only" do
    rows = csv_rows(build_xlsx([ [ "Name", "Units" ], [ "Alpha Fund", 12.5 ] ]))

    assert_equal [ [ "Name", "Units" ], [ "Alpha Fund", "12.5" ] ], rows
  end

  test "reads inline strings" do
    assert_equal [ [ "a", "b" ] ], csv_rows(build_xlsx([ [ "a", "b" ] ], inline: true))
  end

  test "keeps columns aligned for sparse cells and keeps empty rows" do
    rows = csv_rows(build_xlsx([ [ "A", nil, "C" ], nil, [ nil, "B2" ] ]))

    assert_equal [ [ "A", nil, "C" ], [ nil, nil, nil ], [ nil, "B2", nil ] ], rows
  end

  test "quotes cells that contain commas and quotes" do
    assert_equal [ [ "Fund, Direct \"Growth\"", "1" ] ], csv_rows(build_xlsx([ [ "Fund, Direct \"Growth\"", 1 ] ]))
  end

  test "numeric cells with a date format become ISO dates and other numbers stay numbers" do
    rows = csv_rows(build_xlsx([ [ Date.new(2025, 1, 10), 6000, 120.5 ] ]))

    assert_equal [ [ "2025-01-10", "6000", "120.5" ] ], rows
  end

  test "float noise is trimmed" do
    bytes = build_xlsx([ [ 1 ] ]).then do |_|
      build_xlsx([ [ 1 ] ], extra_entries: {
        "xl/worksheets/sheet1.xml" => %(<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1"><v>0.30000000000000004</v></c><c r="B1"><v>1.0E3</v></c><c r="C1"><v>0.1</v></c></row></sheetData></worksheet>)
      })
    end

    assert_equal [ [ "0.3", "1000", "0.1" ] ], csv_rows(bytes)
  end

  test "detects xlsx by content and not by name" do
    assert Import::XlsxReader.xlsx?(build_xlsx([ [ "a" ] ]))
    assert_not Import::XlsxReader.xlsx?("a,b,c\n1,2,3\n")
    assert_not Import::XlsxReader.xlsx?(zip_entries("notes.txt" => "hello"))
  end

  test "a zip that is not a workbook is rejected with a clear message" do
    error = assert_raises(Import::XlsxReader::Error) { Import::XlsxReader.to_csv(zip_entries("notes.txt" => "hello")) }

    assert_match "not an Excel workbook", error.message
  end

  test "old binary xls files are rejected with advice" do
    xls = "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b + ("\x00" * 100)

    error = assert_raises(Import::XlsxReader::Error) { Import::XlsxReader.to_csv(xls) }

    assert_match "save it as .xlsx or CSV", error.message
  end

  test "refuses workbooks with too many entries" do
    entries = (1..(Import::XlsxReader::MAX_ENTRIES + 1)).to_h { |i| [ "xl/extra/#{i}.xml", "<a/>" ] }

    error = assert_raises(Import::XlsxReader::Error) { Import::XlsxReader.to_csv(build_xlsx([ [ "a" ] ], extra_entries: entries)) }

    assert_match "too many parts", error.message
  end

  test "refuses workbooks that expand beyond the size cap" do
    stub_const(Import::XlsxReader, :MAX_TOTAL_BYTES, 1.kilobyte) do
      error = assert_raises(Import::XlsxReader::Error) do
        Import::XlsxReader.to_csv(build_xlsx([ [ "a" ] ], extra_entries: { "xl/media/big.bin" => "0" * 5_000 }))
      end

      assert_match "too large", error.message
    end
  end

  test "refuses a single entry that expands beyond its cap" do
    stub_const(Import::XlsxReader, :MAX_ENTRY_BYTES, 200) do
      error = assert_raises(Import::XlsxReader::Error) do
        Import::XlsxReader.to_csv(build_xlsx([ [ "a" ] * 100 ]))
      end

      assert_match "too large", error.message
    end
  end

  test "refuses XML with a DTD or entities and never loads external files" do
    secret = Rails.root.join("tmp", "xxe_probe.txt")
    File.write(secret, "TOP-SECRET")
    xxe = %(<?xml version="1.0"?><!DOCTYPE sst [<!ENTITY x SYSTEM "file://#{secret}">]><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>&x;</t></si></sst>)

    error = assert_raises(Import::XlsxReader::Error) do
      Import::XlsxReader.to_csv(build_xlsx([ [ "a" ] ], extra_entries: { "xl/sharedStrings.xml" => xxe }))
    end

    assert_match "unsupported XML", error.message
  ensure
    File.delete(secret) if secret && File.exist?(secret)
  end

  test "malformed XML is reported, not raised as a parser error" do
    assert_raises(Import::XlsxReader::Error) do
      Import::XlsxReader.to_csv(build_xlsx([ [ "a" ] ], extra_entries: { "xl/worksheets/sheet1.xml" => "<worksheet><sheetData><row>" }))
    end
  end

  private
    def stub_const(klass, name, value)
      original = klass.const_get(name)
      klass.send(:remove_const, name)
      klass.const_set(name, value)
      yield
    ensure
      klass.send(:remove_const, name)
      klass.const_set(name, original)
    end
end
