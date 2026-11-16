require "zip"

# Turns the first worksheet of an Excel (.xlsx) workbook into CSV text, so every CSV-based import can
# accept a spreadsheet exported from a broker or bank. No gem beyond rubyzip and Nokogiri is needed.
#
# Cells keep their column position (sparse cells are padded), shared and inline strings are resolved,
# numbers are written without float noise, and numeric cells with a date format become ISO dates.
# Text cells are copied as they are.
#
# The workbook is untrusted input: the number and the uncompressed size of the zip entries are capped
# (zip bombs), DTDs and entities are refused, and nothing is fetched from the network.
class Import::XlsxReader
  class Error < StandardError; end

  ZIP_MAGIC = "PK\x03\x04".b.freeze
  OLE_MAGIC = "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b.freeze
  WORKBOOK_ENTRY = "xl/workbook.xml".freeze

  MAX_ENTRIES = 1_000
  MAX_ENTRY_BYTES = 25.megabytes
  MAX_TOTAL_BYTES = 50.megabytes
  MAX_ROWS = 100_000
  MAX_COLUMNS = 16_384 # Excel's limit (column XFD)

  EXCEL_EPOCH = Date.new(1899, 12, 30)
  # Number format ids Excel reserves for dates and times
  BUILTIN_DATE_FORMATS = ([ 14..22, 27..36, 45..47, 50..58 ].flat_map(&:to_a)).to_set.freeze

  class << self
    # True when the bytes are an .xlsx workbook: a zip that contains xl/workbook.xml. The file name is not trusted.
    def xlsx?(bytes)
      bytes = bytes.to_s.b
      return false unless bytes.start_with?(ZIP_MAGIC)

      found = false
      Zip::File.open_buffer(StringIO.new(bytes)) { |zip| found = !zip.find_entry(WORKBOOK_ENTRY).nil? }
      found
    rescue Zip::Error
      false
    end

    # True for a file this reader should handle or explain (an xlsx, an old .xls or some other zip)
    def spreadsheet?(bytes)
      bytes = bytes.to_s.b
      bytes.start_with?(ZIP_MAGIC) || bytes.start_with?(OLE_MAGIC)
    end

    # CSV text for the first worksheet. Raises Error with a message fit for the user.
    def to_csv(bytes)
      new(bytes).to_csv
    end
  end

  def initialize(bytes)
    @bytes = bytes.to_s.b
  end

  def to_csv
    raise Error, "Old Excel files (.xls) are not supported. Open the file in Excel and save it as .xlsx or CSV, then upload that." if @bytes.start_with?(OLE_MAGIC)
    raise Error, "This file is not an Excel workbook. Upload an .xlsx or CSV file." unless self.class.xlsx?(@bytes)

    csv = nil

    Zip::File.open_buffer(StringIO.new(@bytes)) do |zip|
      check_limits!(zip)
      @zip = zip
      @bytes_read = 0

      csv = sheet_rows(sheet_path).map { |cells| CSV.generate_line(cells) }.join
    end

    csv
  rescue Zip::Error, Nokogiri::XML::SyntaxError => error
    raise Error, "Could not read this Excel file (#{error.class.name.demodulize.underscore.humanize.downcase}). Save it again as .xlsx or CSV."
  end

  private
    def check_limits!(zip)
      raise Error, "This Excel file has too many parts to be read safely." if zip.size > MAX_ENTRIES
      raise Error, "This Excel file is too large to read safely." if zip.entries.sum(&:size) > MAX_TOTAL_BYTES
    end

    # Reads at most MAX_ENTRY_BYTES of an entry, whatever its header claims, and at most MAX_TOTAL_BYTES in all
    def read_entry(name)
      entry = @zip.find_entry(name)
      return nil if entry.nil?

      data = +"".b
      entry.get_input_stream do |io|
        while (chunk = io.read(64.kilobytes))
          data << chunk
          @bytes_read += chunk.bytesize
          raise Error, "This Excel file is too large to read safely." if data.bytesize > MAX_ENTRY_BYTES || @bytes_read > MAX_TOTAL_BYTES
        end
      end
      data
    end

    def xml(name)
      data = read_entry(name)
      return nil if data.nil?

      # Workbooks never carry a DTD; refusing it rules out entity expansion tricks outright
      raise Error, "This Excel file contains unsupported XML." if data.match?(/<!DOCTYPE|<!ENTITY/i)

      document = Nokogiri::XML(data) { |config| config.strict.nonet.nocdata }
      document.remove_namespaces!
      document
    end

    # Path of the first worksheet in workbook order
    def sheet_path
      workbook = xml(WORKBOOK_ENTRY)
      sheet = workbook.at_xpath("//sheets/sheet")
      raise Error, "This Excel file has no worksheets." if sheet.nil?

      relationship_id = sheet["id"]
      rels = xml("xl/_rels/workbook.xml.rels")
      target = rels&.at_xpath("//Relationship[@Id='#{relationship_id}']")&.[]("Target") if relationship_id
      target ||= "worksheets/sheet1.xml"

      path = target.start_with?("/") ? target.delete_prefix("/") : "xl/#{target}"
      path = path.gsub(%r{/\./}, "/")
      raise Error, "This Excel file has no readable worksheet." unless @zip.find_entry(path)

      path
    end

    def shared_strings
      @shared_strings ||= begin
        doc = xml("xl/sharedStrings.xml")
        doc ? doc.xpath("//sst/si").map { |item| text_of(item) } : []
      end
    end

    # Plain and rich text, without phonetic hints
    def text_of(node)
      node.xpath("./t | ./r/t").map(&:text).join
    end

    # Style index => true when the cell format shows a date
    def date_styles
      @date_styles ||= begin
        doc = xml("xl/styles.xml")
        custom = doc ? doc.xpath("//numFmts/numFmt").to_h { |fmt| [ fmt["numFmtId"].to_i, fmt["formatCode"].to_s ] } : {}

        formats = doc ? doc.xpath("//cellXfs/xf").map { |xf| xf["numFmtId"].to_i } : []
        formats.each_with_index.filter_map do |format_id, style|
          style if BUILTIN_DATE_FORMATS.include?(format_id) || date_format_code?(custom[format_id])
        end.to_set
      end
    end

    def date_format_code?(code)
      return false if code.blank?

      stripped = code.gsub(/"[^"]*"|\[[^\]]*\]|\\.|_.|\*./, "")
      stripped.match?(/[dmyhs]/i)
    end

    # Array of rows; each row is an array of strings (nil for empty cells), padded to the widest row
    def sheet_rows(path)
      doc = xml(path)
      grid = {}
      width = 0
      last_row = 0

      doc.xpath("//sheetData/row").each_with_index do |row_node, index|
        row_number = (row_node["r"] || (last_row + 1)).to_i
        row_number = index + 1 if row_number < 1
        raise Error, "This worksheet has too many rows to import." if row_number > MAX_ROWS

        last_row = row_number
        next_column = 0

        row_node.xpath("./c").each do |cell|
          column = cell["r"] ? column_index(cell["r"]) : next_column
          next_column = column + 1
          raise Error, "This worksheet has too many columns to import." if column >= MAX_COLUMNS

          value = cell_value(cell)
          next if value.empty?

          (grid[row_number] ||= {})[column] = value
          width = [ width, column + 1 ].max
        end
      end

      (1..last_row).map do |number|
        cells = grid[number] || {}
        Array.new(width) { |column| cells[column] }
      end
    end

    # "AB12" => 27 (zero-based column)
    def column_index(reference)
      letters = reference[/\A[A-Za-z]+/].to_s.upcase
      raise Error, "This worksheet has an invalid cell reference." if letters.empty?

      letters.each_char.reduce(0) { |sum, char| sum * 26 + (char.ord - 64) } - 1
    end

    def cell_value(cell)
      case cell["t"]
      when "s"
        shared_strings[cell.at_xpath("./v")&.text.to_i].to_s
      when "inlineStr"
        text_of(cell.at_xpath("./is") || cell)
      when "str"
        cell.at_xpath("./v")&.text.to_s
      when "b"
        cell.at_xpath("./v")&.text == "1" ? "TRUE" : "FALSE"
      when "e"
        ""
      else
        number_value(cell)
      end
    end

    def number_value(cell)
      raw = cell.at_xpath("./v")&.text.to_s.strip
      return "" if raw.empty?
      return raw unless raw.match?(/\A-?\d+(\.\d+)?([eE][+-]?\d+)?\z/)

      if date_styles.include?(cell["s"].to_i) && cell["s"]
        date_text(BigDecimal(raw))
      else
        plain_number(raw)
      end
    end

    # 0.30000000000000004 => "0.3", 1.0E3 => "1000"
    def plain_number(raw)
      return raw if raw.match?(/\A-?\d+\z/)

      decimal = BigDecimal(raw).round(10)
      text = decimal.to_s("F")
      text.sub(/\.0\z/, "").sub(/(\.\d*?)0+\z/, '\1')
    end

    # Excel serial days since 1899-12-30; a fraction is the time of day
    def date_text(serial)
      days = serial.floor
      date = EXCEL_EPOCH + days
      fraction = serial - days
      return date.iso8601 if fraction.zero?

      seconds = (fraction * 86_400).round
      "#{date.iso8601} #{Time.at(seconds).utc.strftime('%H:%M:%S')}"
    rescue Date::Error, RangeError
      serial.to_s("F")
    end
end
