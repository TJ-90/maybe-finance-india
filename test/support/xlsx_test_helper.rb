require "zip"

# Builds minimal .xlsx workbooks for tests (a zip of XML parts), so no spreadsheet file with real data is needed.
#
# `rows` is an array of rows, each an array of cell values placed by position:
#   String  => a shared string (or an inline string with inline: true)
#   Integer / Float => a number
#   Date    => a numeric cell with a date format (the way Excel stores real dates)
#   nil     => no cell at all (a sparse gap)
# A row that is nil or [] leaves that row number out of the sheet, like an empty row in Excel.
module XlsxTestHelper
  def build_xlsx(rows, inline: false, extra_entries: {}, workbook_xml: nil)
    shared = []
    sheet_rows = rows.each_with_index.filter_map do |cells, row_index|
      next if cells.blank?

      row_number = row_index + 1
      cell_xml = cells.each_with_index.filter_map do |value, col_index|
        next if value.nil?

        reference = "#{column_letters(col_index)}#{row_number}"
        case value
        when String
          if inline
            %(<c r="#{reference}" t="inlineStr"><is><t>#{xml_escape(value)}</t></is></c>)
          else
            shared << value unless shared.include?(value)
            %(<c r="#{reference}" t="s"><v>#{shared.index(value)}</v></c>)
          end
        when Date
          %(<c r="#{reference}" s="1"><v>#{(value - Date.new(1899, 12, 30)).to_i}</v></c>)
        else
          %(<c r="#{reference}"><v>#{value}</v></c>)
        end
      end.join

      %(<row r="#{row_number}">#{cell_xml}</row>)
    end.join

    entries = {
      "[Content_Types].xml" => %(<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>),
      "xl/workbook.xml" => workbook_xml || %(<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Transactions" sheetId="1" r:id="rId1"/><sheet name="Second" sheetId="2" r:id="rId2"/></sheets></workbook>),
      "xl/_rels/workbook.xml.rels" => %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="worksheet" Target="worksheets/sheet2.xml"/></Relationships>),
      "xl/styles.xml" => %(<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="dd\\-mmm\\-yyyy"/></numFmts><cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="164"/><xf numFmtId="2"/></cellXfs></styleSheet>),
      "xl/sharedStrings.xml" => %(<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">#{shared.map { |s| "<si><t>#{xml_escape(s)}</t></si>" }.join}</sst>),
      "xl/worksheets/sheet1.xml" => %(<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{sheet_rows}</sheetData></worksheet>),
      "xl/worksheets/sheet2.xml" => %(<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>second sheet</t></is></c></row></sheetData></worksheet>)
    }.merge(extra_entries)

    zip_entries(entries)
  end

  # A zip with the given name => content entries
  def zip_entries(entries)
    Zip::OutputStream.write_buffer do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end.string
  end

  # Synthetic Groww mutual fund order history in the layout of a real export: a personal details block,
  # a title line, blank rows, the header, two blank rows and then the orders, newest first.
  # `orders` are [scheme, type, units, nav, amount (text), date (text)].
  def groww_orders_xlsx(orders, **options)
    rows = [
      nil, nil,
      [ "Personal Details" ],
      [ "Name", "Asha Kumar" ],
      [ "Mobile Number", "9999999999" ],
      [ "PAN", "ABCDE1234F" ],
      nil, nil,
      [ "TRANSACTIONS FROM Apr 01 2016 TO Nov 17 2026" ],
      nil,
      [ "Scheme Name", "Transaction Type", "Units", "NAV", "Amount", "Date" ],
      nil, nil
    ] + orders.map { |order| order.map(&:to_s) }

    build_xlsx(rows, **options)
  end

  def xlsx_upload(bytes, filename: "order_history.xlsx")
    Rack::Test::UploadedFile.new(
      StringIO.new(bytes), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      original_filename: filename
    )
  end

  private
    def column_letters(index)
      letters = +""
      number = index + 1
      while number.positive?
        number, remainder = (number - 1).divmod(26)
        letters.prepend((65 + remainder).chr)
      end
      letters
    end

    def xml_escape(text)
      ERB::Util.html_escape(text)
    end
end
