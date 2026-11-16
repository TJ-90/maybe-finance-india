# Writes the system-generated entries of a fixed deposit during account sync.
#
# * Value accruals: a valuation at every month end from the start date, one at maturity and one
#   for today, so the balance chart follows the interest. The balance calculators treat a valuation
#   as "the balance on that date", which is exactly what an accrual is.
# * Interest payouts (payout FDs only): an income transaction for each payout date.
#
# Every entry is marked with `generated_by`, so the whole set is deleted and recreated on each run
# (see Account::GeneratedEntries). User-entered valuations and edited generated entries are never
# touched, and no accrual is written on a date that already has a valuation.
class FixedDeposit::Accruer
  VALUE_SOURCE = "fixed_deposit_value".freeze
  PAYOUT_SOURCE = "fixed_deposit_payout".freeze

  def initialize(fixed_deposit, as_of: Date.current)
    @fixed_deposit = fixed_deposit
    @as_of = as_of
  end

  def accrue!
    return unless account.present? && fixed_deposit.start_date.present? && fixed_deposit.maturity_date.present?

    account.replace_generated_entries!(VALUE_SOURCE, value_specs)
    account.replace_generated_entries!(PAYOUT_SOURCE, payout_specs)
  end

  def value_dates
    return [] if fixed_deposit.payout_fd? || as_of < fixed_deposit.start_date

    last_day = fixed_deposit.auto_renew? && !fixed_deposit.recurring? ? as_of : [ as_of, fixed_deposit.maturity_date ].min

    dates = month_ends(fixed_deposit.start_date, last_day)
    dates << fixed_deposit.maturity_date if fixed_deposit.maturity_date <= as_of
    dates << as_of
    dates.uniq.sort
  end

  def payout_dates
    months = FixedDeposit::PAYOUT_MONTHS[fixed_deposit.payout]
    return [] if months.nil? || fixed_deposit.recurring?

    last_day = [ as_of, fixed_deposit.maturity_date ].min
    dates = []
    k = 1

    while (date = fixed_deposit.start_date >> (k * months)) <= last_day
      dates << date
      k += 1
    end

    dates
  end

  private
    attr_reader :fixed_deposit, :as_of

    def account
      fixed_deposit.account
    end

    def value_specs
      value_dates.map do |date|
        {
          date: date,
          name: "Accrued value",
          amount: fixed_deposit.value_on(date),
          entryable: Valuation.new(kind: "reconciliation")
        }
      end
    end

    def payout_specs
      amount = fixed_deposit.payout_amount
      return [] if amount.zero?

      category = account.family.categories.find_by(name: "Interest")

      payout_dates.map do |date|
        {
          date: date,
          name: "Interest payout",
          amount: -amount, # negative amount = income
          entryable: Transaction.new(kind: "standard", category: category)
        }
      end
    end

    def month_ends(from, to)
      dates = []
      date = from.end_of_month

      while date <= to
        dates << date
        date = (date + 1.day).end_of_month
      end

      dates
    end
end
