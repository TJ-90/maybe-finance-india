# Writes the yearly interest credits of a provident fund as system-generated transactions during
# account sync. Same mechanism as FixedDeposit::Accruer: the generated set is deleted and recreated
# on every run, user-entered entries are never touched, and an interest entry the user has edited
# is kept as is (no new one is generated for that date).
class ProvidentFund::InterestPoster
  SOURCE = "provident_fund_interest".freeze

  def initialize(provident_fund, as_of: Date.current)
    @provident_fund = provident_fund
    @as_of = as_of
  end

  def post!
    account = provident_fund.account
    return if account.nil?

    account.replace_generated_entries!(SOURCE, specs)
  end

  private
    attr_reader :provident_fund, :as_of

    def specs
      scheme = provident_fund.subtype.to_s.upcase

      ProvidentFund::InterestCalculator.new(provident_fund, as_of: as_of).credits.map do |credit|
        {
          date: credit.date,
          name: "#{scheme} interest FY #{credit.financial_year}".squish,
          amount: -credit.amount, # negative amount = inflow
          # one_time keeps credited interest out of monthly income/expense analytics: it is not spendable cash flow
          entryable: Transaction.new(kind: "one_time")
        }
      end
    end
end
