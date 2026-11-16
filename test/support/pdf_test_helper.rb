require "digest"

# Builds tiny single-page text PDFs for tests, optionally locked with a user password
# (standard security handler, RC4 128 bit, revision 3). No real statements are involved.
module PdfTestHelper
  PASSWORD_PADDING = [
    "28BF4E5E4E758A4164004E56FFFA01082E2E00B6D0683E802F0CA9FE6453697A"
  ].pack("H*")

  def build_pdf(lines, password: nil)
    PdfBuilder.new(lines, password: password).to_s
  end

  class PdfBuilder
    def initialize(lines, password: nil)
      @lines = lines
      @password = password
      @file_id = Digest::MD5.digest("synthetic-test-pdf")
    end

    def to_s
      encrypt! if @password
      objects = []

      objects << "<< /Type /Catalog /Pages 2 0 R >>"
      objects << "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
      objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>"
      objects << stream_object(content_stream, 4)
      # Explicit widths (monospaced) so text positions do not depend on font metric files
      objects << "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding " \
                 "/FirstChar 32 /LastChar 126 /Widths [#{(['600'] * 95).join(' ')}] >>"
      objects << encrypt_dictionary if @password

      body = "%PDF-1.6\n".b
      offsets = []

      objects.each_with_index do |object, index|
        offsets << body.bytesize
        body << "#{index + 1} 0 obj\n".b << object.b << "\nendobj\n".b
      end

      xref_offset = body.bytesize
      body << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n".b
      offsets.each { |offset| body << format("%010d 00000 n \n", offset).b }

      trailer = "<< /Size #{objects.size + 1} /Root 1 0 R /ID [<#{@file_id.unpack1('H*')}> <#{@file_id.unpack1('H*')}>]"
      trailer += " /Encrypt 6 0 R" if @password
      trailer += " >>"

      body << "trailer\n#{trailer}\nstartxref\n#{xref_offset}\n%%EOF\n".b
      body
    end

    private
      def content_stream
        ops = [ "BT", "/F1 9 Tf", "11 TL", "40 800 Td" ]
        @lines.each { |line| ops << "(#{escape(line)}) Tj T*" }
        ops << "ET"
        ops.join("\n")
      end

      def escape(text)
        text.gsub("\\", "\\\\\\\\").gsub("(", "\\(").gsub(")", "\\)")
      end

      def stream_object(data, object_number)
        data = rc4(object_key(object_number), data) if @password
        "<< /Length #{data.bytesize} >>\nstream\n".b + data.b + "\nendstream".b
      end

      def encrypt_dictionary
        "<< /Filter /Standard /V 2 /R 3 /Length 128 /P #{@permissions} " \
          "/O <#{@owner_entry.unpack1('H*')}> /U <#{@user_entry.unpack1('H*')}> >>"
      end

      # Algorithms 2, 3 and 5 of the PDF 1.7 spec for revision 3 security handlers
      def encrypt!
        @permissions = -4
        padded = pad(@password)
        @owner_entry = compute_owner_entry(padded)
        permission_bytes = [ @permissions ].pack("l<")

        digest = Digest::MD5.digest(padded + @owner_entry + permission_bytes + @file_id)
        50.times { digest = Digest::MD5.digest(digest[0, 16]) }
        @key = digest[0, 16]

        hash = Digest::MD5.digest(PASSWORD_PADDING + @file_id)
        data = rc4(@key, hash)
        (1..19).each { |i| data = rc4(@key.bytes.map { |b| b ^ i }.pack("C*"), data) }
        @user_entry = data + ("\x00".b * 16)
      end

      def compute_owner_entry(padded_user)
        digest = Digest::MD5.digest(padded_user)
        50.times { digest = Digest::MD5.digest(digest) }
        key = digest[0, 16]
        data = rc4(key, padded_user)
        (1..19).each { |i| data = rc4(key.bytes.map { |b| b ^ i }.pack("C*"), data) }
        data
      end

      def object_key(object_number)
        Digest::MD5.digest(@key + [ object_number ].pack("V")[0, 3] + [ 0 ].pack("v"))[0, 16]
      end

      def pad(password)
        (password.b + PASSWORD_PADDING)[0, 32]
      end

      def rc4(key, data)
        s = (0..255).to_a
        j = 0
        key_bytes = key.bytes
        256.times do |i|
          j = (j + s[i] + key_bytes[i % key_bytes.size]) % 256
          s[i], s[j] = s[j], s[i]
        end

        i = j = 0
        data.bytes.map do |byte|
          i = (i + 1) % 256
          j = (j + s[i]) % 256
          s[i], s[j] = s[j], s[i]
          byte ^ s[(s[i] + s[j]) % 256]
        end.pack("C*")
      end
  end
end
