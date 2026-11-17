require "test_helper"

class Demo::GeneratorTest < ActiveSupport::TestCase
  # Generating and syncing takes about half a minute, so this is one test with several sections
  # rather than one run per test. WebMock (loaded in test_helper) raises on any HTTP request, so a
  # green run also proves that generating and syncing the demo needs no network.
  test "generates a complete, offline Indian household" do
    capture_io { Demo::Generator.new(seed: 7).generate_default_data!(skip_clear: true, email: "demo-india@example.com") }
    @family = User.find_by!(email: "demo-india@example.com").family

    assert_household
    assert_members
    assert_investments
    assert_bank_lines
    assert_planning
    assert_monitoring
    assert_assistant
  end

  private
    def assert_household
      assert_equal [ "INR", "IN", "Asia/Kolkata", "%d-%m-%Y" ], [ @family.currency, @family.country, @family.timezone, @family.date_format ]
      assert @family.india?
      assert_equal "partner_demo-india@example.com", @family.users.find_by(role: "member").email

      types = @family.accounts.map(&:accountable_type)
      %w[Depository CreditCard Investment ProvidentFund FixedDeposit PreciousMetal Property Loan].each { |type| assert_includes types, type }
      assert_equal %w[epf ppf], @family.accounts.where(accountable_type: "ProvidentFund").pluck(:subtype).sort
      assert @family.accounts.all? { |account| account.currency == "INR" }
      assert_equal [ "active" ], @family.accounts.map(&:status).uniq
    end

    def assert_members
      rahul = @family.household_members.find_by!(relationship: "self")
      asha = @family.household_members.find_by!(relationship: "spouse")

      assert_equal [ "Rahul Sharma", "nri" ], [ rahul.name, rahul.residency_status ]
      assert_equal [ "Asha Sharma", "resident" ], [ asha.name, asha.residency_status ]
      assert_equal rahul, @family.users.find_by!(role: "admin").household_member
      assert_equal %w[nre nro], @family.accounts.where(household_member: rahul, accountable_type: "Depository").pluck(:subtype).sort
      assert_equal rahul, @family.accounts.find_by!(name: "Zerodha Demat").household_member
      assert_equal asha, @family.accounts.find_by!(name: "Mutual Funds – Asha").household_member
      assert_nil @family.accounts.find_by!(name: "HDFC Home Loan").household_member_id

      nri_report = TaxCenter::Report.new(family: @family, accounts: @family.accounts_with_investments.where(household_member: rahul).to_a,
                                         residency: TaxCenter::Residency.new(member: rahul))
      assert nri_report.tds_total.positive?, "expected Rahul's sales to carry an estimated TDS"
      assert @family.accounts_with_investments.where(household_member: asha).any?

      interest = TaxCenter::InterestIncome.new(
        family: @family, accounts: @family.accounts.where(household_member: rahul).to_a,
        financial_year_start: Period.financial_year_start(Date.current), residency: TaxCenter::Residency.new(member: rahul)
      )
      assert interest.exempt_total.positive?, "expected NRE interest"
      assert interest.taxable_total.positive?, "expected NRO interest"
    end

    def assert_investments
      demat = @family.accounts.find_by!(name: "Zerodha Demat")
      assert_equal %w[INFY NIFTYBEES RELIANCE TCS], demat.trades.map { |t| t.security.ticker }.uniq.sort
      assert_equal [ Security::NSE_MIC ], demat.trades.map { |t| t.security.exchange_operating_mic }.uniq

      funds = @family.accounts.find_by!(name: "Mutual Funds – Asha")
      securities = funds.trades.map(&:security).uniq
      assert_equal 3, securities.size
      assert_equal [ Security::AMFI_MIC ], securities.map(&:exchange_operating_mic).uniq
      assert funds.trades.all? { |trade| trade.folio_number.present? }
      assert securities.all? { |security| security.offline? && security.isin.present? && security.mutual_fund_scheme.present? }

      securities.each do |security|
        assert security.prices.exists?(date: Date.current), "#{security.ticker} has no price for today"
      end

      trade_names = @family.entries.where(entryable_type: "Trade").pluck(:name)
      assert trade_names.any?
      assert trade_names.all? { |name| name.match?(/\A(Buy|Sell) [\d.]+ (units of Sample .+ Fund - Direct Plan - Growth|shares of [A-Z]+)\z/) }, trade_names.uniq.inspect
      assert trade_names.none? { |name| name.match?(/\b9000\d\d\b/) }

      assert_equal 3, funds.current_holdings.count
      assert demat.current_holdings.count.positive?
    end

    def assert_bank_lines
      modes = @family.transactions.where.not(payment_mode: nil).distinct.pluck(:payment_mode)
      assert_includes modes, "upi"
      assert_includes modes, "nach"
      assert @family.transactions.where(payment_mode: "upi").where.not(reference_number: nil).exists?
      assert @family.merchants.exists?
    end

    def assert_planning
      assert_equal %w[health term], @family.insurance_policies.pluck(:kind).sort
      assert @family.insurance_policies.premium_due_within(30.days).exists?

      assert_equal %w[education emergency_fund retirement], @family.goals.pluck(:kind).sort
      assert @family.goals.all? { |goal| goal.goal_allocations.any? }

      report = TaxCenter::Report.new(family: @family, accounts: @family.accounts_with_investments.to_a)
      assert report.lines.any?, "expected realized gains in the current financial year"

      assert @family.investment_summary.xirr
    end

    def assert_monitoring
      @family.goals.each do |goal|
        assert_operator goal.goal_snapshots.count, :>=, 90, "#{goal.name} has no status history"
        assert_equal Date.current, goal.latest_snapshot.date
      end

      education = @family.goals.find_by!(kind: "education")
      assert education.last_status_change, "expected a status change in the demo history"

      admin = @family.users.find_by!(role: "admin")
      kinds = admin.notifications.pluck(:kind)
      assert_includes kinds, "goal_status"
      assert_includes kinds, "stale_account"
      assert admin.notifications.unread.any?
      assert_no_match(/\d{3}/, admin.notifications.find_by!(kind: "goal_status").title)
    end

    def assert_assistant
      user = @family.users.find_by!(role: "admin")

      assert_equal 2, Assistant::Function::GetHoldings.new(user).call[:accounts].size
      assert_equal 3, Assistant::Function::GetGoals.new(user).call[:goals].size
      assert Assistant::Function::GetTaxSummary.new(user).call({})[:sales_count].positive?
    end
end
