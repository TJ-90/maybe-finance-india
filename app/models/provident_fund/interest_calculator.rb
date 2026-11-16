# Computes the yearly interest credited to an EPF / VPF / PPF / SSY account.
#
# * EPF and VPF: the EPFO method. Interest for each month is (month-end running balance) x rate / 12.
# * PPF and SSY: interest for each month is the lowest balance between the 5th and the month end
#   x rate / 12. We approximate "lowest balance between the 5th and month end" with the balance on
#   the 5th (it is exact unless money is withdrawn after the 5th).
#
# Interest is credited once a year, on 31 March, and rounded to the nearest rupee. It is not
# compounded within the year but becomes part of the balance the next year.
#
# Rates are looked up per month (ProvidentFund#rate_on), so a mid-year rate change is honoured.
class ProvidentFund::InterestCalculator
  Credit = Data.define(:date, :amount, :financial_year)

  # Interest for one financial year, given a way to read balances and rates.
  #
  #   method:        :monthly_running_balance or :balance_on_fifth
  #   fy_start_year: 2025 for FY 2025-26
  #   balance_on:    ->(date) { balance }
  #   rate_on:       ->(date) { rate in % p.a. }
  #   last_date:     samples after this date earn nothing (e.g. SSY maturity)
  def self.annual_interest(method:, fy_start_year:, balance_on:, rate_on:, last_date: nil)
    total = (0..11).sum(BigDecimal("0")) do |i|
      first_of_month = Date.new(fy_start_year, 4, 1) >> i
      sample_date = method == :monthly_running_balance ? first_of_month.end_of_month : first_of_month + 4.days

      next BigDecimal("0") if last_date && sample_date > last_date

      balance = [ balance_on.call(sample_date).to_d, 0 ].max
      rate = rate_on.call(sample_date).to_d

      balance * rate / 1200
    end

    total.round(0)
  end

  def self.financial_year_label(fy_start_year)
    "#{fy_start_year}-#{(fy_start_year + 1).to_s.last(2)}"
  end

  def initialize(provident_fund, as_of: Date.current)
    @provident_fund = provident_fund
    @as_of = as_of
  end

  # All interest credits due up to `as_of`, oldest first. Each year's credit feeds the next year's balance.
  def credits
    @credits ||= compute_credits
  end

  private
    attr_reader :provident_fund, :as_of

    def account
      provident_fund.account
    end

    def compute_credits
      return [] if account.nil? || timeline.empty?

      computed = []
      first_year = financial_year_start(timeline.first.date)

      (first_year..).each do |fy_start_year|
        credit_date = Date.new(fy_start_year + 1, 3, 31)
        break if credit_date > as_of

        amount = self.class.annual_interest(
          method: provident_fund.interest_method,
          fy_start_year: fy_start_year,
          balance_on: ->(date) { balance_on(date, computed) },
          rate_on: ->(date) { provident_fund.rate_on(date) || 0 },
          last_date: provident_fund.maturity_date
        )

        next if amount.zero?

        computed << Credit.new(date: credit_date, amount: amount, financial_year: self.class.financial_year_label(fy_start_year))
      end

      computed
    end

    # Balance at the end of `date`: the latest valuation (or the opening balance), plus the
    # transactions since, plus interest already credited in earlier years.
    def balance_on(date, credits_so_far)
      balance = BigDecimal("0")

      timeline.each do |event|
        break if event.date > date

        balance = event.valuation ? event.amount : balance - event.amount
      end

      balance + credits_so_far.select { |credit| credit.date <= date }.sum(BigDecimal("0")) { |credit| credit.amount }
    end

    TimelineEvent = Data.define(:date, :amount, :valuation)

    # User-entered history only: valuations and transactions, with our own generated interest left out
    # (it is recomputed here). On the same day transactions come before valuations, as in the balance calculators.
    def timeline
      @timeline ||= account.entries
        .where(entryable_type: %w[Valuation Transaction])
        .where("entries.generated_by IS DISTINCT FROM ? OR entries.generated_user_edited", ProvidentFund::InterestPoster::SOURCE)
        .order(:date)
        .to_a
        .sort_by { |entry| [ entry.date, entry.valuation? ? 1 : 0 ] }
        .map { |entry| TimelineEvent.new(date: entry.date, amount: entry.amount, valuation: entry.valuation?) }
    end

    def financial_year_start(date)
      date.month >= 4 ? date.year : date.year - 1
    end
end
