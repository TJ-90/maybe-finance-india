# Interest a person earned in one financial year, split into taxable and exempt, by account.
#
# * Fixed deposits: payout FDs pay interest out as generated income entries (`entries.generated_by`);
#   cumulative FDs and RDs build it up inside the deposit (FixedDeposit#interest_accrued_between).
#   Taxable.
# * Provident funds: the yearly interest credit is a generated entry. PPF, SSY and EPF interest is exempt
#   (EPF only up to the yearly contribution limit, which is noted).
# * Bank accounts: credited interest found in the transactions. NRE interest is exempt for an NRI, NRO
#   and ordinary savings interest is taxable.
#
# Indicative only: set-offs such as Sec 80TTA are not modelled. Rules come from config/india_capital_gains.yml.
class TaxCenter::InterestIncome
  Row = Struct.new(:account, :label, :amount, :exempt, :notes, :tds, keyword_init: true) do
    def taxable
      exempt ? BigDecimal("0") : amount
    end

    def exempt_amount
      exempt ? amount : BigDecimal("0")
    end
  end

  attr_reader :family, :residency, :rules

  def initialize(family:, accounts:, financial_year_start:, residency: nil, rules: TaxCenter::Rules.current)
    @family = family
    @accounts = accounts.to_a
    @financial_year_start = financial_year_start
    @rules = rules
    @residency = residency || TaxCenter::Residency.new(rules: rules)
  end

  def period
    @period ||= Period.financial_year_for(@financial_year_start)
  end

  def label
    Period.financial_year_label(@financial_year_start)
  end

  # Accounts that earned interest this year (an account with none is left out)
  def rows
    @rows ||= @accounts.filter_map { |account| row_for(account) }.select { |row| row.amount.nonzero? }
                       .sort_by { |row| [ row.exempt ? 1 : 0, row.account.name ] }
  end

  def taxable_total
    rows.sum(BigDecimal("0")) { |row| row.taxable }
  end

  def exempt_total
    rows.sum(BigDecimal("0")) { |row| row.exempt_amount }
  end

  # Notes that depend on residency: the bank TDS threshold for residents, NRO TDS for NRIs
  def notes
    notes = []

    if residency.nri?
      notes << "NRO account interest is taxable in India and the bank deducts TDS at #{interest_rules[:nri_nro_tds_rate]}% (plus surcharge and cess). NRE account interest is exempt for an NRI."
    else
      threshold = rules.resident_interest_tds_threshold(period.end_date)
      notes << "Banks deduct #{interest_rules[:resident_tds_rate]}% TDS when interest from one bank is above #{money(threshold[:general])} a year (#{money(threshold[:senior_citizen])} for senior citizens). Interest below that is still taxable."
    end

    notes << "Deductions such as Sec 80TTA and the slab-rate tax on this interest are not computed."
    notes
  end

  private
    def interest_rules
      rules.interest_rules
    end

    def row_for(account)
      case account.accountable_type
      when "FixedDeposit" then fixed_deposit_row(account)
      when "ProvidentFund" then provident_fund_row(account)
      when "Depository" then bank_row(account)
      end
    end

    def fixed_deposit_row(account)
      deposit = account.accountable
      amount = generated_total(account, FixedDeposit::Accruer::PAYOUT_SOURCE)
      amount = deposit.interest_accrued_between(period.start_date, period.end_date) if amount.zero?
      notes = []
      notes << "Taxable at your slab rate, every year, even if the interest is only paid at maturity."
      notes << "If this is an NRE deposit its interest is exempt for an NRI. It is treated as taxable here." if residency.nri?

      Row.new(account: account, label: account.long_subtype_label, amount: convert(account, amount), exempt: false, notes: notes)
    end

    def provident_fund_row(account)
      amount = generated_total(account, ProvidentFund::InterestPoster::SOURCE)
      notes = []

      case account.subtype
      when "ppf" then notes << "PPF interest is exempt."
      when "ssy" then notes << "Sukanya Samriddhi interest is exempt."
      else
        limits = interest_rules[:epf_contribution_limit]
        notes << "EPF interest is exempt, but interest on your own contributions above #{money(limits[:with_employer_contribution])} a year (#{money(limits[:without_employer_contribution])} with no employer contribution) is taxable. Verify each year."
        notes << "For an NRI, EPF interest stays exempt only while the account is operative. It becomes taxable about three years after the account goes inactive." if residency.nri?
      end

      Row.new(account: account, label: account.long_subtype_label, amount: convert(account, amount), exempt: true, notes: notes)
    end

    def bank_row(account)
      amount = bank_interest(account)
      subtype = account.subtype
      nri = residency.nri?
      exempt = subtype == "nre" && nri
      notes = []
      tds = nil

      if subtype == "nre" && !nri
        notes << "NRE interest is exempt only for an NRI. Residents must redesignate NRE accounts, so this is treated as taxable."
      elsif exempt
        notes << "NRE interest is exempt for an NRI."
      elsif subtype == "nro" && nri
        rate = interest_rules[:nri_nro_tds_rate]
        converted = convert(account, amount)
        tds = (converted * rate / 100 * (1 + residency.cess_percent / 100)).round(2)
        notes << "NRO interest is taxable. Estimated TDS at #{rate}% plus #{residency.cess_percent.to_s('F').delete_suffix('.0')}% cess; surcharge is not included."
      else
        notes << "Savings interest is taxable at your slab rate."
      end

      Row.new(account: account, label: account.long_subtype_label, amount: convert(account, amount), exempt: exempt, notes: notes, tds: tds)
    end

    # Interest credits are transactions whose narration is an interest credit (the bank import parser names
    # them "Interest credit"). Generated entries are never counted twice.
    def bank_interest(account)
      -account.entries.where(entryable_type: "Transaction", generated_by: nil, date: period.start_date..period.end_date)
              .where("entries.amount < 0")
              .where("entries.name ILIKE 'interest%' OR entries.name ILIKE 'int.pd%'")
              .sum(:amount)
    end

    # Credited interest is stored as inflows (negative amounts) by generated entries
    def generated_total(account, source)
      -account.entries.where(generated_by: source, date: period.start_date..period.end_date).sum(:amount)
    end

    def convert(account, amount)
      Money.new(amount, account.currency).exchange_to(family.currency, fallback_rate: 1).amount
    end

    def money(amount)
      Money.new(amount, family.currency).format(precision: 0)
    end
end
