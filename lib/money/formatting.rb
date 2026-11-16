module Money::Formatting
  include ActiveSupport::NumberHelper

  def format(options = {})
    locale = options[:locale] || I18n.locale
    default_opts = format_options(locale)

    number_to_currency(amount, default_opts.merge(options))
  end
  alias_method :to_s, :format

  INDIAN_DELIMITER_PATTERN = /(\d+?)(?=(\d\d)+(\d)(?!\d))/

  # Compact format for tight spaces. INR uses K / L (lakh) / Cr (crore), other currencies use K / M / B.
  #   INR: ₹950, ₹45.6K, ₹12.35 L, ₹1.20 Cr    Others: $950, $45.6K, $1.23M, $1.50B
  def format_compact(options = {})
    absolute = amount.abs
    scale = compact_scale(absolute)

    number = if scale.nil?
      number_to_rounded(absolute, precision: 0, delimiter: currency.delimiter, significant: false)
    else
      divisor, suffix, precision = scale.values_at(:divisor, :suffix, :precision)
      scaled = number_to_rounded(absolute / divisor, precision: precision, separator: currency.separator, strip_insignificant_zeros: scale[:strip_zeros])
      "#{scaled}#{suffix}"
    end

    unit = options.fetch(:unit, get_symbol)
    formatted = currency.default_format.sub("%u", unit).sub("%n", number)
    amount.negative? && number.match?(/[1-9]/) ? "-#{formatted}" : formatted
  end

  def format_options(locale = nil)
    local_option_overrides = locale_options(locale)

    {
      unit: get_symbol,
      precision: currency.default_precision,
      delimiter: currency.delimiter,
      separator: currency.separator,
      format: currency.default_format
    }.merge(grouping_options).merge(local_option_overrides)
  end

  private
    # Indian grouping: 12,34,56,789 (last three digits, then pairs)
    def grouping_options
      currency.indian_grouping? ? { delimiter_pattern: INDIAN_DELIMITER_PATTERN } : {}
    end

    COMPACT_BASE = { divisor: 1, suffix: "", precision: 0 }.freeze
    COMPACT_THOUSANDS = { divisor: 1_000, suffix: "K", precision: 1, strip_zeros: true }.freeze
    INDIAN_COMPACT_SCALES = [
      COMPACT_BASE, COMPACT_THOUSANDS,
      { divisor: 100_000, suffix: " L", precision: 2 },
      { divisor: 10_000_000, suffix: " Cr", precision: 2 }
    ].freeze
    INTERNATIONAL_COMPACT_SCALES = [
      COMPACT_BASE, COMPACT_THOUSANDS,
      { divisor: 1_000_000, suffix: "M", precision: 2 },
      { divisor: 1_000_000_000, suffix: "B", precision: 2 }
    ].freeze

    # The unit to display `absolute` in, or nil when it is shown in full (below 1,000). A value that
    # rounds up to the next unit's size moves to that unit, so 999,999.999 reads "1.00M", not "1000K".
    def compact_scale(absolute)
      scales = currency.indian_grouping? ? INDIAN_COMPACT_SCALES : INTERNATIONAL_COMPACT_SCALES
      index = scales.rindex { |scale| absolute >= scale[:divisor] } || 0

      while (larger = scales[index + 1])
        scale = scales[index]
        rounded = (absolute / scale[:divisor]).round(scale[:precision]) * scale[:divisor]
        break if rounded < larger[:divisor]

        index += 1
      end

      index.zero? ? nil : scales[index]
    end

    def get_symbol
      if currency.symbol == "$" && currency.iso_code != "USD"
        [ currency.iso_code.first(2), currency.symbol ].join
      else
        currency.symbol
      end
    end

    def locale_options(locale)
      case [ currency.iso_code, locale.to_sym ]
      when [ "EUR", :nl ], [ "EUR", :pt ]
        { delimiter: ".", separator: ",", format: "%u %n" }
      when [ "EUR", :en ], [ "EUR", :en_IE ]
        { delimiter: ",", separator: "." }
      else
        {}
      end
    end
end
