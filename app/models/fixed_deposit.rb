class FixedDeposit < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "fd" => { short: "FD", long: "Fixed Deposit" },
    "rd" => { short: "RD", long: "Recurring Deposit" },
    "nsc" => { short: "NSC", long: "National Savings Certificate" },
    "kvp" => { short: "KVP", long: "Kisan Vikas Patra" },
    "scss" => { short: "SCSS", long: "Senior Citizens' Savings Scheme" },
    "pomis" => { short: "POMIS", long: "Post Office Monthly Income Scheme" },
    "corporate_fd" => { short: "Corporate FD", long: "Corporate Fixed Deposit" }
  }.freeze

  # Compounding periods per year. "simple" means no compounding.
  COMPOUNDING = {
    "monthly" => 12,
    "quarterly" => 4,
    "half_yearly" => 2,
    "yearly" => 1,
    "simple" => nil
  }.freeze

  # Months between interest payouts. "cumulative" means interest is reinvested until maturity.
  PAYOUT_MONTHS = {
    "cumulative" => nil,
    "monthly" => 1,
    "quarterly" => 3,
    "yearly" => 12
  }.freeze

  validates :interest_rate, numericality: { greater_than_or_equal_to: 0, less_than: 100 }
  validates :compounding, inclusion: { in: COMPOUNDING.keys }
  validates :payout, inclusion: { in: PAYOUT_MONTHS.keys }
  validates :start_date, :maturity_date, presence: true
  validates :principal, numericality: { greater_than: 0 }, allow_nil: true
  validates :monthly_installment, numericality: { greater_than: 0 }, allow_nil: true
  validate :principal_or_installment_present
  validate :maturity_after_start

  after_update_commit :sync_opening_anchor_and_account, if: :terms_changed?

  class << self
    def color
      "#7C3AED"
    end

    def icon
      "landmark"
    end

    def classification
      "asset"
    end
  end

  def recurring?
    account&.subtype == "rd"
  end

  def payout_fd?
    !recurring? && PAYOUT_MONTHS[payout].present?
  end

  def balance_display_name
    "current value"
  end

  def opening_balance_display_name
    "amount invested"
  end

  # Used when the account is created: the balance on the start date.
  def opening_balance_date
    start_date
  end

  def opening_balance_amount
    value_on(start_date)
  end

  # What the deposit is worth on `date`, following the formulas Indian banks use.
  #
  # FD:  P * (1 + r/n)^(n*t), n = compounding periods per year (quarterly by default), t in years.
  # RD:  sum over installments of P * (1 + r/n)^(n*t_i), t_i being that installment's age in years.
  # Payout FD: principal stays flat; the interest is paid out as income entries (see Accruer).
  #
  # The value freezes at maturity unless the FD is set to auto-renew, in which case it keeps
  # compounding at the same rate (renewing at the same rate is the same as compounding on).
  def value_on(date)
    return BigDecimal("0") if start_date.nil? || date < start_date

    if recurring?
      recurring_value_on(date)
    elsif payout_fd?
      principal.to_d
    else
      compounded_value_on(date)
    end
  end

  def value_money_on(date)
    Money.new(value_on(date), account.currency)
  end

  def maturity_value
    value_on(maturity_date)
  end

  # Interest paid out per payout period for a payout FD (simple interest on the flat principal)
  def payout_amount
    months = PAYOUT_MONTHS[payout]
    return BigDecimal("0") unless months && principal.present?

    (principal.to_d * interest_rate.to_d / 100 * months / 12).round(2)
  end

  def matured?(date = Date.current)
    maturity_date.present? && date >= maturity_date && !auto_renew?
  end

  def tenure_months
    return 0 if start_date.nil? || maturity_date.nil?

    months_between(start_date, maturity_date)
  end

  def generate_auto_entries!
    FixedDeposit::Accruer.new(self).accrue!
  end

  # Interest that builds up inside the deposit between two dates (cumulative FD, RD, NSC...): growth in
  # value minus what was deposited in the period. Payout FDs pay their interest out as income entries,
  # so they have none here.
  def interest_accrued_between(from, to)
    return BigDecimal("0") if start_date.nil? || payout_fd? || to < from

    growth = value_on(to) - value_on(from - 1.day)
    (growth - deposited_between(from, to)).round(2)
  end

  def trend
    Trend.new(current: account.balance_money, previous: account.first_valuation_amount)
  end

  # Time in years from `from` to `to`: whole months count as exact twelfths, leftover days as days/365.
  # A deposit held for exactly one year therefore has t == 1, whatever the leap-year situation.
  def year_fraction(from, to)
    return BigDecimal("0") if to <= from

    months = months_between(from, to)
    leftover_days = (to - (from >> months)).to_i

    BigDecimal(months) / 12 + BigDecimal(leftover_days) / 365
  end

  private
    def deposited_between(from, to)
      if recurring?
        count = (0...tenure_months).count { |k| (start_date >> k).between?(from, to) }
        monthly_installment.to_d * count
      else
        start_date.between?(from, to) ? principal.to_d : BigDecimal("0")
      end
    end

    def valuation_end(date)
      return date if auto_renew? && !recurring?

      [ date, maturity_date ].compact.min
    end

    def compounded_value_on(date)
      t = year_fraction(start_date, valuation_end(date))
      (principal.to_d * growth_factor(t)).round(2)
    end

    # Installments fall on the start date and every month after it, one per month of tenure
    def recurring_value_on(date)
      end_date = valuation_end(date)

      total = (0...tenure_months).sum(BigDecimal("0")) do |k|
        installment_date = start_date >> k
        next BigDecimal("0") if installment_date > end_date

        monthly_installment.to_d * growth_factor(year_fraction(installment_date, end_date))
      end

      total.round(2)
    end

    def growth_factor(t)
      rate = interest_rate.to_d / 100
      periods = COMPOUNDING.fetch(compounding)

      if periods.nil?
        1 + rate * t
      else
        BigDecimal(((1 + rate / periods).to_f**(periods * t.to_f)).to_s)
      end
    end

    # Whole calendar months from `from` to `to` (not counting a part month)
    def months_between(from, to)
      months = (to.year - from.year) * 12 + (to.month - from.month)
      months -= 1 if (from >> months) > to
      months
    end

    def principal_or_installment_present
      return if principal.present? || monthly_installment.present?

      errors.add(:principal, "or monthly installment must be provided")
    end

    def maturity_after_start
      return if start_date.blank? || maturity_date.blank?

      errors.add(:maturity_date, "must be after the start date") if maturity_date <= start_date
    end

    def terms_changed?
      (saved_changes.keys & %w[principal monthly_installment start_date maturity_date interest_rate compounding payout auto_renew]).any?
    end

    # The opening anchor is the deposit's value on its start date, so keep it in step with the terms.
    # Syncing then regenerates the accruals.
    def sync_opening_anchor_and_account
      return if account.nil?

      anchor = account.valuations.opening_anchor.includes(:entry).first&.entry

      if anchor_out_of_date?(anchor)
        # Drop generated entries first: one may sit on the new anchor date (valuations are unique per date)
        account.entries.auto_generated.destroy_all
        anchor.update!(date: start_date, amount: opening_balance_amount)
      end

      account.sync_later
    end

    def anchor_out_of_date?(anchor)
      anchor.present? && (anchor.date != start_date || anchor.amount != opening_balance_amount)
    end
end
