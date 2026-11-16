class Period
  include ActiveModel::Validations, Comparable

  class InvalidKeyError < StandardError; end

  attr_reader :key, :start_date, :end_date

  validates :start_date, :end_date, presence: true, if: -> { PERIODS[key].nil? }
  validates :key, presence: true, if: -> { start_date.nil? || end_date.nil? }
  validate :must_be_valid_date_range

  PERIODS = {
    "last_day" => {
      date_range: -> { [ 1.day.ago.to_date, Date.current ] },
      label_short: "1D",
      label: "Last Day",
      comparison_label: "vs. yesterday"
    },
    "current_week" => {
      date_range: -> { [ Date.current.beginning_of_week, Date.current ] },
      label_short: "WTD",
      label: "Current Week",
      comparison_label: "vs. start of week"
    },
    "last_7_days" => {
      date_range: -> { [ 7.days.ago.to_date, Date.current ] },
      label_short: "7D",
      label: "Last 7 Days",
      comparison_label: "vs. last week"
    },
    "current_month" => {
      date_range: -> { [ Date.current.beginning_of_month, Date.current ] },
      label_short: "MTD",
      label: "Current Month",
      comparison_label: "vs. start of month"
    },
    "last_30_days" => {
      date_range: -> { [ 30.days.ago.to_date, Date.current ] },
      label_short: "30D",
      label: "Last 30 Days",
      comparison_label: "vs. last month"
    },
    "last_90_days" => {
      date_range: -> { [ 90.days.ago.to_date, Date.current ] },
      label_short: "90D",
      label: "Last 90 Days",
      comparison_label: "vs. last quarter"
    },
    "current_year" => {
      date_range: -> { [ Date.current.beginning_of_year, Date.current ] },
      label_short: "YTD",
      label: "Current Year",
      comparison_label: "vs. start of year"
    },
    "current_financial_year" => {
      date_range: -> { [ financial_year_start(Date.current), Date.current ] },
      label_short: "FYTD",
      label: -> { "Current FY (#{financial_year_label(Date.current)})" },
      comparison_label: "vs. start of financial year"
    },
    "last_financial_year" => {
      date_range: -> { financial_year_range(financial_year_start(Date.current).year - 1) },
      label_short: "Last FY",
      label: "Last FY",
      comparison_label: "vs. start of last financial year"
    },
    "last_365_days" => {
      date_range: -> { [ 365.days.ago.to_date, Date.current ] },
      label_short: "365D",
      label: "Last 365 Days",
      comparison_label: "vs. 1 year ago"
    },
    "last_5_years" => {
      date_range: -> { [ 5.years.ago.to_date, Date.current ] },
      label_short: "5Y",
      label: "Last 5 Years",
      comparison_label: "vs. 5 years ago"
    }
  }

  class << self
    def from_key(key)
      unless PERIODS.key?(key)
        raise InvalidKeyError, "Invalid period key: #{key}"
      end

      start_date, end_date = PERIODS[key].fetch(:date_range).call

      new(key: key, start_date: start_date, end_date: end_date)
    end

    # Indian financial year runs April 1 to March 31.
    FINANCIAL_YEAR_START_MONTH = 4

    # First day of the financial year containing the given date
    def financial_year_start(date)
      year = date.month >= FINANCIAL_YEAR_START_MONTH ? date.year : date.year - 1
      Date.new(year, FINANCIAL_YEAR_START_MONTH, 1)
    end

    # Full April-March range for the financial year starting in the given calendar year
    def financial_year_range(start_year)
      start_date = Date.new(start_year, FINANCIAL_YEAR_START_MONTH, 1)
      [ start_date, start_date.next_year.prev_day ]
    end

    # Period covering the whole financial year that contains the given date
    def financial_year_for(date)
      start_date, end_date = financial_year_range(financial_year_start(date).year)
      new(start_date: start_date, end_date: end_date)
    end

    # e.g. "2026-27"
    def financial_year_label(date)
      start_year = financial_year_start(date).year
      "#{start_year}-#{(start_year + 1).to_s.last(2)}"
    end

    def custom(start_date:, end_date:)
      new(start_date: start_date, end_date: end_date)
    end

    def all
      PERIODS.map { |key, period| from_key(key) }
    end

    def as_options
      all.map { |period| [ period.label_short, period.key ] }
    end
  end

  PERIODS.each do |key, period|
    define_singleton_method(key) do
      from_key(key)
    end
  end

  def initialize(start_date: nil, end_date: nil, key: nil, date_format: "%b %d, %Y")
    @key = key
    @start_date = start_date
    @end_date = end_date
    @date_format = date_format
    validate!
  end

  def <=>(other)
    [ start_date, end_date ] <=> [ other.start_date, other.end_date ]
  end

  def date_range
    start_date..end_date
  end

  def days
    (end_date - start_date).to_i + 1
  end

  def within?(other)
    start_date >= other.start_date && end_date <= other.end_date
  end

  def interval
    if days > 366
      "1 week"
    else
      "1 day"
    end
  end

  def label
    if key_metadata
      label = key_metadata.fetch(:label)
      label.respond_to?(:call) ? label.call : label
    else
      "Custom Period"
    end
  end

  def label_short
    if key_metadata
      key_metadata.fetch(:label_short)
    else
      "Custom"
    end
  end

  def comparison_label
    if key_metadata
      key_metadata.fetch(:comparison_label)
    else
      "#{start_date.strftime(@date_format)} to #{end_date.strftime(@date_format)}"
    end
  end

  private
    def key_metadata
      @key_metadata ||= PERIODS[key]
    end

    def must_be_valid_date_range
      return if start_date.nil? || end_date.nil?
      unless start_date.is_a?(Date) && end_date.is_a?(Date)
        errors.add(:start_date, "must be a valid date, got #{start_date.inspect}")
        errors.add(:end_date, "must be a valid date, got #{end_date.inspect}")
        return
      end

      errors.add(:start_date, "must be before end date") if start_date > end_date
    end
end
