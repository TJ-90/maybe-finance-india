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

    def compact_scale(absolute)
      if currency.indian_grouping?
        if absolute >= 10_000_000
          { divisor: 10_000_000, suffix: " Cr", precision: 2 }
        elsif absolute >= 100_000
          { divisor: 100_000, suffix: " L", precision: 2 }
        elsif absolute >= 1_000
          { divisor: 1_000, suffix: "K", precision: 1, strip_zeros: true }
        end
      elsif absolute >= 1_000_000_000
        { divisor: 1_000_000_000, suffix: "B", precision: 2 }
      elsif absolute >= 1_000_000
        { divisor: 1_000_000, suffix: "M", precision: 2 }
      elsif absolute >= 1_000
        { divisor: 1_000, suffix: "K", precision: 1, strip_zeros: true }
      end
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
