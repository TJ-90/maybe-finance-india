require "open3"
require "tempfile"

# Pulls the text out of a CAS PDF, in memory and inside the request. The PDF and its password are
# never stored and never leave this object: callers keep only the extracted text.
#
# Password-protected statements (CAMS / KFintech lock them with the investor's PAN, or a password
# chosen on MFCentral / CAMS) are decrypted by pdf-reader. If pdf-reader can't handle a file's
# encryption and the `qpdf` CLI is installed, qpdf is used as a fallback.
class CasImport::PdfText
  Error = Class.new(CasImport::Error)
  PasswordRequiredError = Class.new(Error)
  InvalidPasswordError = Class.new(Error)
  UnreadablePdfError = Class.new(Error)
  UnsupportedEncryptionError = Class.new(Error)

  MAX_BYTES = 15.megabytes
  UNREADABLE = [ PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError, PDF::Reader::InvalidObjectError, PDF::Reader::InvalidPageError ].freeze

  class << self
    # file: an uploaded file / IO, or a binary String with the PDF bytes
    def extract(file, password: nil)
      new(file, password: password).text
    end

    def qpdf_available?
      system("qpdf", "--version", out: File::NULL, err: File::NULL) == true
    rescue Errno::ENOENT
      false
    end
  end

  def initialize(file, password: nil)
    @data = read_bytes(file)
    @password = password.to_s.strip.presence
  end

  def text
    raise UnreadablePdfError, "That file is not a PDF." unless @data.start_with?("%PDF")

    read_text(@data, @password)
  rescue PDF::Reader::EncryptedPDFError
    raise_password_error
  rescue *UNREADABLE => error
    text_via_qpdf(error)
  end

  private
    def read_bytes(file)
      raw = (file.respond_to?(:read) ? file.read : file.to_s).to_s.b
      raise UnreadablePdfError, "That PDF is too large." if raw.bytesize > MAX_BYTES
      raw
    end

    def read_text(bytes, password)
      reader = PDF::Reader.new(StringIO.new(bytes), password: password.to_s)
      reader.pages.map(&:text).join("\n")
    end

    def raise_password_error
      if @password.nil?
        raise PasswordRequiredError, "This PDF is password protected. Enter its password (usually your PAN in capitals, or the one you set on CAMS / MFCentral)."
      else
        raise InvalidPasswordError, "That password did not unlock the PDF. Check it and try again."
      end
    end

    def text_via_qpdf(original_error)
      unless self.class.qpdf_available?
        raise UnsupportedEncryptionError, "We couldn't read this PDF (#{original_error.class.name.demodulize.underscore.humanize.downcase}). If it is password protected, please upload an unlocked copy of the statement."
      end

      read_text(decrypt_with_qpdf, nil)
    rescue PDF::Reader::EncryptedPDFError, *UNREADABLE
      raise UnreadablePdfError, "We couldn't read this PDF."
    end

    # The password goes through a short-lived file (never the command line, where other processes could
    # see it). Every temp file is deleted before this method returns.
    def decrypt_with_qpdf
      Tempfile.create([ "cas-in", ".pdf" ], binmode: true) do |input|
        input.write(@data)
        input.flush

        Tempfile.create([ "cas-pw", ".txt" ]) do |password_file|
          password_file.write(@password.to_s)
          password_file.flush

          Tempfile.create([ "cas-out", ".pdf" ]) do |output|
            _out, err, status = Open3.capture3("qpdf", "--password-file=#{password_file.path}", "--decrypt", input.path, output.path)

            # qpdf exits with 3 when it only produced warnings
            unless status.success? || status.exitstatus == 3
              raise InvalidPasswordError, "That password did not unlock the PDF. Check it and try again." if err.match?(/invalid password/i)
              raise UnreadablePdfError, "We couldn't decrypt this PDF."
            end

            File.binread(output.path)
          end
        end
      end
    end
end
