class Demo::Generator
  # @param seed [Integer, String, nil] Seed value used to initialise the internal PRNG. If nil, the ENV variable DEMO_DATA_SEED will
  #   be honoured and default to a random seed when not present.
  #
  # Initialising an explicit PRNG gives us repeatable demo datasets while still
  #   allowing truly random data when the caller does not care about
  #   determinism.  The global `Kernel.rand` and helpers like `Array#sample`
  #   will also be seeded so that *all* random behaviour inside this object –
  #   including library helpers that rely on Ruby's global RNG – follow the
  #   same deterministic sequence.
  def initialize(seed: ENV.fetch("DEMO_DATA_SEED", nil))
    # Convert the seed to an Integer if one was provided, otherwise fall back
    # to a random, but memoised, seed so the generator instance can report it
    # back to callers when needed (e.g. for debugging a specific run).
    @seed = seed.present? ? seed.to_i : Random.new_seed

    # Internal PRNG instance – use this instead of the global RNG wherever we
    # explicitly call `rand` inside the class.  We override `rand` below so
    # existing method bodies automatically delegate here without requiring
    # widespread refactors.
    @rng = Random.new(@seed)

    # Also seed Ruby's global RNG so helpers that rely on it (e.g.
    # Array#sample, Kernel.rand in invoked libraries, etc.) remain
    # deterministic for the lifetime of this generator instance.
    srand(@seed)
  end

  # Expose the seed so callers can reproduce a run if necessary.
  attr_reader :seed

  # Generate empty family - no financial data
  def generate_empty_data!(skip_clear: false)
    with_timing(__method__) do
      unless skip_clear
        puts "🧹 Clearing existing data..."
        clear_all_data!
      end

      puts "👥 Creating empty family..."
      create_family_and_users!("Sharma Household", "user@example.com", onboarded: true, subscribed: true)

      puts "✅ Empty demo data loaded successfully!"
    end
  end

  # Generate new user family - no financial data, needs onboarding
  def generate_new_user_data!(skip_clear: false)
    with_timing(__method__) do
      unless skip_clear
        puts "🧹 Clearing existing data..."
        clear_all_data!
      end

      puts "👥 Creating new user family..."
      create_family_and_users!("Sharma Household", "user@example.com", onboarded: false, subscribed: false)

      puts "✅ New user demo data loaded successfully!"
    end
  end

  # Generate a realistic Indian household: bank, card, demat and mutual fund accounts with two and a
  # half years of history, EPF/PPF/FD/gold, a home loan, insurance and three goals. Everything is in
  # INR and all security prices are seeded, so generating (and syncing) never needs the network.
  def generate_default_data!(skip_clear: false, email: "user@example.com")
    if skip_clear
      puts "⏭️  Skipping data clearing (appending new family)..."
    else
      puts "🧹 Clearing existing data..."
      clear_all_data!
    end

    with_timing(__method__, max_seconds: 1000) do
      puts "👥 Creating demo family..."
      family = create_family_and_users!("Sharma Household", email, onboarded: true, subscribed: true)
      @family = family

      puts "📊 Creating realistic financial data..."
      family.categories.bootstrap!
      create_securities!
      create_accounts!
      create_transactions!
      create_investments!
      create_insurance_policies!

      puts "🔄 Syncing accounts (balances, holdings, FD accruals, PF interest)..."
      sync_family_accounts!(family)

      create_goals!(family)
      # Auto-fill current-month budget based on recent spending averages
      generate_budget_auto_fill!(family)

      puts "✅ Realistic demo data loaded successfully!"
    end
  end


  private

    HISTORY_MONTHS = 30
    MF_AMC = "Sample Mutual Fund".freeze

    # Prices follow a smooth deterministic curve: base * e^(mu t) with a gentle swing, so the demo has
    # plausible gains and losses without any randomness or network. `base` is the price on START_DATE.
    SECURITY_SPECS = {
      reliance: { ticker: "RELIANCE", mic: "XNSE", name: "Reliance Industries Ltd", kind: "stock", asset_class: "equity", tax: "equity", isin: "INE002A01018", base: 2450, mu: 0.09, swing: 0.04, phase: 0.0 },
      tcs: { ticker: "TCS", mic: "XNSE", name: "Tata Consultancy Services Ltd", kind: "stock", asset_class: "equity", tax: "equity", isin: "INE467B01029", base: 3300, mu: 0.07, swing: 0.03, phase: 1.1 },
      infy: { ticker: "INFY", mic: "XNSE", name: "Infosys Ltd", kind: "stock", asset_class: "equity", tax: "equity", isin: "INE009A01021", base: 1450, mu: 0.05, swing: 0.05, phase: 2.3 },
      niftybees: { ticker: "NIFTYBEES", mic: "XNSE", name: "Nippon India ETF Nifty 50 BeES", kind: "etf", asset_class: "equity", tax: "equity", isin: "INF204KB14I2", base: 245, mu: 0.11, swing: 0.02, phase: 0.6 },
      flexi: { ticker: "900001", mic: "AMFI", name: "Sample Flexi Cap Fund - Direct Plan - Growth", kind: "mutual_fund", asset_class: "equity", tax: "equity", isin: "INF9D0001014", base: 62, mu: 0.15, swing: 0.025, phase: 0.3, category: "Equity Scheme - Flexi Cap Fund", folio: "12345678/90" },
      index: { ticker: "900002", mic: "AMFI", name: "Sample Nifty 50 Index Fund - Direct Plan - Growth", kind: "mutual_fund", asset_class: "equity", tax: "equity", isin: "INF9D0002012", base: 118, mu: 0.12, swing: 0.02, phase: 0.9, category: "Other Scheme - Index Funds", folio: "4567890123" },
      liquid: { ticker: "900003", mic: "AMFI", name: "Sample Liquid Fund - Direct Plan - Growth", kind: "mutual_fund", asset_class: "debt", tax: "debt", isin: "INF9D0003010", base: 1250, mu: 0.068, swing: 0.0, phase: 0.0, category: "Debt Scheme - Liquid Fund", folio: "9876543/21" }
    }.freeze

    UPI_MERCHANTS = {
      bigbasket: [ "BIGBASKET", "bigbasket@hdfcbank", "HDFC0000001", "Groceries", 1200..4500 ],
      dmart: [ "DMART", "dmart@icici", "ICIC0000001", "Groceries", 2500..6500 ],
      swiggy: [ "SWIGGY", "swiggy@icici", "ICIC0000001", "Food Delivery & Dining", 250..900 ],
      zomato: [ "ZOMATO", "zomato@hdfcbank", "HDFC0000001", "Food Delivery & Dining", 250..800 ],
      uber: [ "UBER INDIA", "uber@axisbank", "UTIB0000001", "Transport & Fuel", 150..650 ],
      apollo: [ "APOLLO PHARMACY", "apollopharmacy@icici", "ICIC0000001", "Healthcare", 300..1800 ]
    }.freeze

    def start_date
      @start_date ||= (HISTORY_MONTHS.months.ago.to_date.beginning_of_month - 1.day)
    end

    # First day of every month from the start of the history up to the current month
    def month_starts
      @month_starts ||= (0..HISTORY_MONTHS).map { |i| Date.current.beginning_of_month << (HISTORY_MONTHS - i) }
    end

    # `day` of the month (clamped to its length), or nil while that day is still in the future
    def day_of(month, day)
      date = [ month + (day - 1).days, month.end_of_month ].min
      date <= Date.current ? date : nil
    end

    def months_ago_date(months, day = 10)
      date = Date.current.beginning_of_month << months
      [ date + (day - 1).days, date.end_of_month ].min
    end

    def inflation_factor(date)
      1.06**((date - start_date) / 365.0)
    end

    # ---------------------------------------------------------------------------
    # Family, securities and prices
    # ---------------------------------------------------------------------------
    def clear_all_data!
      family_count = Family.count
      if family_count > 50
        raise "Too much data to clear efficiently (#{family_count} families). Run 'rails db:reset' instead."
      end
      Demo::DataCleaner.new.destroy_everything!
    end

    def create_family_and_users!(family_name, email, onboarded:, subscribed:)
      family = Family.create!(
        name: family_name,
        currency: "INR",
        locale: "en",
        country: "IN",
        timezone: "Asia/Kolkata",
        date_format: "%d-%m-%Y"
      )

      family.start_subscription!("sub_demo_123") if subscribed

      # Admin user
      family.users.create!(
        email: email,
        first_name: "Asha",
        last_name: "Sharma",
        role: "admin",
        password: "password",
        onboarded_at: onboarded ? Time.current : nil
      )

      # Member user
      family.users.create!(
        email: "partner_#{email}",
        first_name: "Rohan",
        last_name: "Sharma",
        role: "member",
        password: "password",
        onboarded_at: onboarded ? Time.current : nil
      )

      family
    end

    def create_securities!
      @securities = SECURITY_SPECS.to_h do |key, spec|
        security = Security.find_or_initialize_by(ticker: spec[:ticker], exchange_operating_mic: spec[:mic])
        security.update!(
          name: spec[:name],
          kind: spec[:kind],
          asset_class: spec[:asset_class],
          tax_category: spec[:tax],
          isin: spec[:isin],
          country_code: "IN",
          offline: true # prices are seeded below, nothing is ever fetched
        )

        if spec[:mic] == Security::AMFI_MIC
          MutualFundScheme.find_or_initialize_by(scheme_code: spec[:ticker]).update!(
            name: spec[:name], amc: MF_AMC, category: spec[:category], scheme_type: "Open Ended",
            plan: "direct", option: "growth", isin_growth: spec[:isin],
            asset_class: spec[:asset_class], tax_category: spec[:tax],
            latest_nav: price_on(spec, Date.current), nav_date: Date.current, active: true
          )
        end

        [ key, security ]
      end

      seed_prices!
    end

    def price_on(spec, date)
      t = (date - start_date) / 365.0
      value = spec[:base] * Math.exp(spec[:mu] * t) * (1 + spec[:swing] * Math.sin(2 * Math::PI * t * 3 + spec[:phase]))
      value.round(spec[:mic] == Security::AMFI_MIC ? 4 : 2)
    end

    # One price per calendar day from the start of the history to today, so Security::Price::Importer
    # sees nothing missing and no provider is ever called.
    def seed_prices!
      now = Time.current

      SECURITY_SPECS.each do |key, spec|
        rows = (start_date..Date.current).map do |date|
          { security_id: @securities[key].id, date: date, price: price_on(spec, date), currency: "INR", created_at: now, updated_at: now }
        end

        Security::Price.upsert_all(rows, unique_by: %i[security_id date currency])
      end
    end

    # ---------------------------------------------------------------------------
    # Accounts
    # ---------------------------------------------------------------------------
    def create_accounts!
      @hdfc = add_account!(Depository.new, "HDFC Savings Account", subtype: "savings", opening: 450_000)
      @icici_card = add_account!(CreditCard.new, "ICICI Amazon Pay Credit Card", subtype: "credit_card", opening: 0)
      @zerodha = add_account!(Investment.new, "Zerodha Demat", subtype: "demat", opening: 600_000)
      @mf_account = add_account!(Investment.new, "Mutual Funds – Asha", subtype: "mutual_fund", opening: 0)

      @epf = add_account!(
        ProvidentFund.new(opened_on: start_date, monthly_contribution: 21_600, employer_contribution: 20_350, account_number_last4: "4321"),
        "EPF – Asha", subtype: "epf", opening: 420_000
      )
      @ppf = add_account!(
        ProvidentFund.new(opened_on: start_date, monthly_contribution: 12_500, account_number_last4: "8765"),
        "PPF – Asha", subtype: "ppf", opening: 350_000
      )

      fd_start = months_ago_date(8, 12)
      @fd = add_account!(
        FixedDeposit.new(
          interest_rate: 7.1, compounding: "quarterly", payout: "cumulative", principal: 500_000,
          start_date: fd_start, maturity_date: fd_start >> 24, institution_name: "HDFC Bank", auto_renew: false
        ),
        "HDFC Bank FD", subtype: "fd", opening: 500_000, opening_date: fd_start
      )

      @gold = add_account!(PreciousMetal.new(weight_grams: 80, purity: "22k", form: "jewellery"), "Gold jewellery", subtype: "gold", opening: 430_000)
      @flat = add_account!(Property.new(year_built: 2018, area_value: 1250, area_unit: "sqft"), "Flat – Whitefield, Bengaluru", subtype: "residential", opening: 9_800_000)
      @home_loan = add_account!(Loan.new(interest_rate: 8.5, term_months: 240, rate_type: "fixed", initial_balance: 6_200_000), "HDFC Home Loan", subtype: "home", opening: 5_950_000)
    end

    def add_account!(accountable, name, subtype:, opening:, opening_date: start_date)
      account = @family.accounts.create!(accountable: accountable, name: name, subtype: subtype, balance: opening, cash_balance: opening, currency: "INR")
      result = Account::OpeningBalanceManager.new(account).set_opening_balance(balance: opening, date: opening_date)
      raise result.error if result.error

      account
    end

    # ---------------------------------------------------------------------------
    # Day-to-day money: salary, bills, UPI spends, card, EMI, SIP debits
    # ---------------------------------------------------------------------------
    def create_transactions!
      @category = @family.categories.index_by(&:name)
      loan_balance = @home_loan.opening_anchor_balance
      card_charges = 0

      month_starts.each_with_index do |month, index|
        puts "   📅 #{month.strftime('%b %Y')}" if (index % 12).zero?
        factor = inflation_factor(month)

        generate_income!(month)
        generate_housing_and_bills!(month, factor)
        generate_upi_spends!(month, factor)
        loan_balance = generate_home_loan_payment!(month, loan_balance)
        generate_sip_debits!(month)
        generate_retirement_contributions!(month)

        # The previous month's card statement is paid on the 5th
        if (paid_on = day_of(month, 5)) && card_charges.positive?
          create_transfer!(@hdfc, @icici_card, card_charges, "ICICI credit card bill payment", paid_on)
        end
        card_charges = generate_card_spends!(month, factor)
      end

      generate_periodic_items!
      generate_gold_and_property_valuations!
    end

    def generate_income!(month)
      return unless (date = day_of(month, 1))

      fiscal_step = 1.08**((date - start_date).to_i / 365)
      salary = (190_000 * fiscal_step).round(-2)
      create_bank_transaction!(@hdfc, -salary, "NEFT CR-HDFC0000001-ACME TECHNOLOGIES PVT LTD-SALARY #{date.strftime('%b%Y')}-HDFCN#{ref(11)}", "Salary", date)
    end

    def generate_housing_and_bills!(month, factor)
      if (date = day_of(month, 3))
        create_bank_transaction!(@hdfc, (4_500 * factor).round(-1), upi("GREEN VALLEY APARTMENT OWNERS", "greenvalley@okhdfcbank", "HDFC0000001"), "Rent & Housing", date)
      end
      if (date = day_of(month, 8))
        create_bank_transaction!(@hdfc, 8_000, upi("LAKSHMI DEVI", "lakshmi@paytm", "PYTM0000001"), "Domestic Help", date)
      end
      if (date = day_of(month, 12))
        create_bank_transaction!(@hdfc, jitter(2_400 * factor, 0.3).round(-1), upi("BESCOM", "bescom@icici", "ICIC0000001"), "Utilities", date)
      end
      if (date = day_of(month, 14))
        create_bank_transaction!(@hdfc, 1_179, upi("AIRTEL", "airtelbroadband@icici", "ICIC0000001"), "Utilities", date)
        create_bank_transaction!(@hdfc, 749, upi("JIO", "jio@icici", "ICIC0000001"), "Utilities", date)
      end
    end

    def generate_upi_spends!(month, factor)
      counts = { bigbasket: 3, dmart: 2, swiggy: 5, zomato: 3, uber: 4, apollo: 1 }

      counts.each do |key, count|
        name, vpa, ifsc, category, range = UPI_MERCHANTS.fetch(key)
        count.times do
          next unless (date = day_of(month, rand(2..28)))

          amount = (rand(range) * factor).round(-1)
          create_bank_transaction!(@hdfc, amount, upi(name, vpa, ifsc), category, date)
        end
      end

      if (date = day_of(month, 20))
        create_bank_transaction!(@hdfc, 5_000, "ATM-CASH WDL-HDFC BANK ATM WHITEFIELD-#{ref(6)}", nil, date)
      end
    end

    # Principal reduces the loan (a transfer to the loan account); the interest part is an expense
    def generate_home_loan_payment!(month, balance)
      return balance unless (date = day_of(month, 5))

      emi = 55_000
      interest = (balance * 0.085 / 12).round(2)
      principal = (emi - interest).round(2)

      create_bank_transaction!(@hdfc, interest, "ACH D- HDFC HOME LOAN-#{ref(10)}", "EMI & Loan Payments", date)
      create_transfer!(@hdfc, @home_loan, principal, "HDFC Home Loan EMI (principal)", date)

      balance - principal
    end

    # SIPs leave the bank on the 7th via NACH and buy units the next day at that day's NAV
    def generate_sip_debits!(month)
      return unless (date = day_of(month, 7))

      { flexi: 20_000, index: 15_000, liquid: 5_000 }.each do |key, amount|
        spec = SECURITY_SPECS.fetch(key)
        buy_date = [ date + 1.day, Date.current ].min
        units = (amount / price_on(spec, buy_date)).floor(3)

        create_bank_transfer!(@hdfc, @mf_account, amount, "ACH D- INDIAN CLEARING CORP-#{ref(10)}", date)
        create_trade!(@mf_account, key, units, buy_date, folio: spec[:folio])
      end
    end

    def generate_retirement_contributions!(month)
      if (date = day_of(month, 2))
        @epf.entries.create!(name: "EPF contribution (employee + employer)", date: date, amount: -41_950, currency: "INR", entryable: Transaction.new(kind: "one_time"))
      end
      if (date = day_of(month, 9))
        create_transfer!(@hdfc, @ppf, 12_500, "PPF contribution", date)
      end
    end

    # Card spends use the card account; returns this month's total so the bill can be paid next month
    def generate_card_spends!(month, factor)
      total = 0

      specs = [
        [ "AMAZON PAY INDIA", "Shopping", 600..5_500, 3 ],
        [ "FLIPKART", "Shopping", 500..4_500, 1 ],
        [ "MYNTRA", "Shopping", 800..3_800, 1 ],
        [ "INDIAN OIL FUEL STATION", "Transport & Fuel", 2_000..3_000, 2 ],
        [ "NETFLIX.COM", "Entertainment & OTT", 649..649, 1 ],
        [ "SPOTIFY", "Entertainment & OTT", 119..119, 1 ],
        [ "PVR CINEMAS", "Entertainment & OTT", 700..1_800, 1 ]
      ]

      specs.each do |name, category, range, count|
        count.times do
          next unless (date = day_of(month, rand(1..27)))

          amount = range.size > 1 ? (rand(range) * factor).round : range.first
          create_transaction!(@icici_card, amount, name, @category[category], date)
          total += amount
        end
      end

      total
    end

    # Yearly and quarterly items
    def generate_periodic_items!
      month_starts.each do |month|
        # School fees every quarter (Apr, Jul, Oct, Jan)
        if [ 1, 4, 7, 10 ].include?(month.month) && (date = day_of(month, 10))
          create_bank_transaction!(@hdfc, (45_000 * inflation_factor(month)).round(-2), "NEFT DR-ICIC0000001-ST JOSEPHS PUBLIC SCHOOL-TUITION FEES-ICICN#{ref(11)}", "Education & School Fees", date)
        end

        # Savings account interest, quarterly
        if [ 1, 4, 7, 10 ].include?(month.month) && (date = day_of(month, 1))
          quarter_end = date - 1.day
          create_bank_transaction!(@hdfc, -rand(3_200..4_800), "INT.PD:#{(quarter_end << 3).strftime('%d-%m-%Y')} TO #{quarter_end.strftime('%d-%m-%Y')}", "Interest", date)
        end

        # Dividends twice a year
        if [ 6, 11 ].include?(month.month) && (date = day_of(month, 18))
          create_bank_transaction!(@hdfc, -rand(1_800..3_200), "ACH C- RELIANCE INDUSTRIES-DIVIDEND-#{ref(8)}", "Dividends", date)
          create_bank_transaction!(@hdfc, -rand(2_000..3_500), "ACH C- TATA CONSULTANCY-DIVIDEND-#{ref(8)}", "Dividends", date)
        end

        # Festival shopping and gifts in October/November
        if [ 10, 11 ].include?(month.month) && (date = day_of(month, 22))
          charge_card!("TANISHQ JEWELLERY", "Gifts & Festivals", rand(12_000..18_000), date)
        end
      end

      # A couple of trips on the card
      [ [ 20, "INDIGO AIRLINES", 18_500 ], [ 20, "IRCTC", 4_200 ], [ 9, "MAKEMYTRIP HOTELS", 24_000 ], [ 9, "INDIGO AIRLINES", 16_800 ], [ 3, "MAKEMYTRIP HOTELS", 31_500 ] ].each do |months, name, amount|
        charge_card!(name, "Travel", amount, months_ago_date(months, 14))
      end

      # Insurance premiums, yearly, on the policy anniversaries
      [ [ term_due_date, "HDFC LIFE INSURANCE", 24_000 ], [ health_due_date, "STAR HEALTH INSURANCE", 18_000 ] ].each do |due, name, amount|
        [ 0, 1, 2 ].each do |years|
          date = due << (12 * (years + 1))
          next if date <= start_date || date > Date.current

          create_bank_transaction!(@hdfc, amount, "NEFT DR-HDFC0000001-#{name}-PREMIUM-HDFCN#{ref(11)}", "Insurance Premiums", date)
        end
      end

      # A routine doctor's visit now and then
      [ 17, 11, 5, 2 ].each do |months|
        create_bank_transaction!(@hdfc, rand(800..2_500), upi("MANIPAL HOSPITALS", "manipalhosp@icici", "ICIC0000001"), "Healthcare", months_ago_date(months, 16))
      end
    end

    def term_due_date
      @term_due_date ||= Date.current + 21.days
    end

    def health_due_date
      @health_due_date ||= Date.current + 140.days
    end

    def generate_gold_and_property_valuations!
      [ [ 18, 540_000 ], [ 6, 610_000 ], [ 0, 660_000 ] ].each do |months, value|
        date = months.zero? ? Date.current : months_ago_date(months, 1)
        @gold.entries.create!(entryable: Valuation.new(kind: months.zero? ? "current_anchor" : "reconciliation"), amount: value, name: "Gold value (22K, 80 g)", currency: "INR", date: date)
      end

      @flat.entries.create!(
        entryable: Valuation.new(kind: "current_anchor"), amount: 11_500_000,
        name: Valuation.build_current_anchor_name(@flat.accountable_type), currency: "INR", date: Date.current
      )
    end

    # ---------------------------------------------------------------------------
    # Investments: stocks on NSE and mutual fund redemptions
    # ---------------------------------------------------------------------------
    def create_investments!
      puts "   📈 Placing stock and ETF trades..."
      [
        [ :reliance, 28, 40 ], [ :reliance, 14, 25 ], [ :tcs, 27, 20 ], [ :infy, 26, 60 ],
        [ :infy, 6, 50 ], [ :niftybees, 25, 200 ], [ :niftybees, 4, 100 ]
      ].each { |key, months, qty| create_trade!(@zerodha, key, qty, months_ago_date(months, 9)) }

      # FIFO sells the oldest units first: the Infosys sale mixes long-term and short-term lots
      create_trade!(@zerodha, :infy, -80, months_ago_date(1, 12))
      create_trade!(@zerodha, :niftybees, -150, months_ago_date(2, 6))

      puts "   🏦 Redeeming some mutual fund units..."
      redeem_units!(:flexi, 300, months_ago_date(3, 15))
      redeem_units!(:liquid, 20, months_ago_date(2, 20))
    end

    # A redemption pays the proceeds back into the savings account
    def redeem_units!(key, units, date)
      spec = SECURITY_SPECS.fetch(key)
      create_trade!(@mf_account, key, -units, date, folio: spec[:folio])
      proceeds = (units * price_on(spec, date)).round(2)

      create_transfer!(@mf_account, @hdfc, proceeds, "#{spec[:name]} redemption", date)
    end

    def create_trade!(account, key, qty, date, folio: nil)
      spec = SECURITY_SPECS.fetch(key)
      price = price_on(spec, date)
      verb = qty.positive? ? "Buy" : "Sell"

      account.entries.create!(
        name: "#{verb} #{qty.abs} #{spec[:ticker]}",
        date: date,
        amount: (qty * price).round(2),
        currency: "INR",
        entryable: Trade.new(qty: qty, price: price, currency: "INR", security: @securities.fetch(key), folio_number: folio)
      )
    end

    # ---------------------------------------------------------------------------
    # Insurance and goals
    # ---------------------------------------------------------------------------
    def create_insurance_policies!
      @family.insurance_policies.create!(
        kind: "term", insurer: "Sample Life Insurance", policy_number: "TERM-DEMO-0001", insured_names: "Asha Sharma",
        currency: "INR", sum_assured: 10_000_000, premium: 24_000, premium_frequency: "yearly",
        next_premium_due_on: term_due_date, start_date: term_due_date << 36, end_date: term_due_date >> (12 * 27), nominee: "Rohan Sharma"
      )
      @family.insurance_policies.create!(
        kind: "health", insurer: "Sample Health Insurance", policy_number: "HLTH-DEMO-0002", insured_names: "Asha, Rohan, Aarav",
        currency: "INR", sum_assured: 1_000_000, premium: 18_000, premium_frequency: "yearly",
        next_premium_due_on: health_due_date, start_date: health_due_date << 36, nominee: "Rohan Sharma"
      )
    end

    def create_goals!(family)
      retirement = family.goals.create!(
        name: "Retirement", kind: "retirement", currency: "INR", current_age: 35, retirement_age: 60, life_expectancy: 85,
        monthly_expenses_today: 85_000, post_retirement_return: 7, monthly_sip: 40_000, sip_step_up_pct: 8,
        initial_equity_pct: 75, final_equity_pct: 30, glide_path_years: 10, target_date: Date.current >> (12 * 25)
      )
      education = family.goals.create!(
        name: "Aarav's education", kind: "education", currency: "INR", target_amount: 4_000_000, target_date: Date.current >> (12 * 12),
        inflation_rate: 8, monthly_sip: 20_000, sip_step_up_pct: 10, initial_equity_pct: 80, final_equity_pct: 20, glide_path_years: 5
      )
      emergency = family.goals.create!(
        name: "Emergency fund", kind: "emergency_fund", currency: "INR", target_amount: 600_000, target_date: Date.current >> 12,
        monthly_sip: 5_000, sip_step_up_pct: 0, initial_equity_pct: 0, final_equity_pct: 0, glide_path_years: 0
      )

      allocate(retirement, @epf, 100)
      allocate(retirement, @ppf, 100)
      allocate(retirement, @zerodha, 100)
      allocate(retirement, @mf_account, 60, security: @securities[:index])
      allocate(education, @mf_account, 100, security: @securities[:flexi])
      allocate(emergency, @fd, 100)
      allocate(emergency, @mf_account, 100, security: @securities[:liquid])
    end

    def allocate(goal, account, percentage, security: nil)
      goal.goal_allocations.create!(account: account, security: security, percentage: percentage)
    end

    # ---------------------------------------------------------------------------
    # Helpers
    # ---------------------------------------------------------------------------
    def create_transaction!(account, amount, name, category, date, kind: nil)
      account.entries.create!(
        entryable: Transaction.new(category: category, kind: kind || "standard"),
        amount: amount,
        name: name,
        currency: account.currency,
        date: date
      )
    end

    # A bank line is parsed like an imported statement: payment mode, reference number, a clean
    # name and a merchant all come from the narration.
    def create_bank_transaction!(account, amount, narration, category_name, date, kind: "standard")
      parsed = Transaction::NarrationParser.parse(narration)
      hint = Transaction::MerchantHint.match(counterparty: parsed[:counterparty], vpa: parsed[:vpa], clean_name: parsed[:clean_name])
      merchant_name = hint&.merchant_name || parsed[:counterparty]
      category = @category[category_name] if category_name
      category ||= @category[hint.category_name] if hint&.category_name

      account.entries.create!(
        entryable: Transaction.new(
          category: category,
          kind: kind,
          merchant: merchant_for(merchant_name),
          payment_mode: parsed[:payment_mode],
          reference_number: parsed[:reference_number]
        ),
        amount: amount,
        name: parsed[:clean_name].presence || narration,
        notes: parsed[:clean_name].present? ? "Bank narration: #{narration}" : nil,
        currency: account.currency,
        date: date
      )
    end

    def merchant_for(name)
      return if name.blank?

      @merchants ||= {}
      @merchants[name.downcase] ||= @family.merchants.where("LOWER(name) = ?", name.downcase).first || @family.merchants.create!(name: name)
    end

    # A one-off card charge that is paid off from the bank a few weeks later
    def charge_card!(name, category_name, amount, date)
      create_transaction!(@icici_card, amount, name, @category[category_name], date)
      paid_on = date + 25.days
      create_transfer!(@hdfc, @icici_card, amount, "ICICI credit card bill payment", paid_on) if paid_on <= Date.current
    end

    def create_transfer!(from_account, to_account, amount, name, date)
      outflow = from_account.entries.create!(
        entryable: Transaction.new(kind: Transfer.kind_for_account(to_account)),
        amount: amount,
        name: name,
        currency: from_account.currency,
        date: date
      )
      inflow = to_account.entries.create!(
        entryable: Transaction.new(kind: "funds_movement"),
        amount: -amount,
        name: name,
        currency: to_account.currency,
        date: date
      )
      Transfer.create!(inflow_transaction: inflow.entryable, outflow_transaction: outflow.entryable)
    end

    # A bank debit with a real-looking narration that is also a transfer to another of the family's accounts
    def create_bank_transfer!(from_account, to_account, amount, narration, date)
      outflow = create_bank_transaction!(from_account, amount, narration, nil, date, kind: Transfer.kind_for_account(to_account))
      inflow = to_account.entries.create!(
        entryable: Transaction.new(kind: "funds_movement"),
        amount: -amount,
        name: outflow.name,
        currency: to_account.currency,
        date: date
      )
      Transfer.create!(inflow_transaction: inflow.entryable, outflow_transaction: outflow.entryable)
    end

    def upi(name, vpa, ifsc)
      "UPI-#{name}-#{vpa}-#{ifsc}-#{ref(12)}-UPI"
    end

    def ref(digits)
      rand(10**(digits - 1)...10**digits).to_s
    end

    # Auto-fill current-month budget based on recent spending averages
    def generate_budget_auto_fill!(family)
      current_month   = Date.current.beginning_of_month
      analysis_start  = (current_month - 3.months).beginning_of_month
      analysis_period = analysis_start..(current_month - 1.day)

      # Fetch expense transactions in the analysis period
      txns = Entry.joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
                  .joins("INNER JOIN categories ON categories.id = transactions.category_id")
                  .where(entries: { entryable_type: "Transaction", date: analysis_period })
                  .where(categories: { classification: "expense", family_id: family.id })

      spend_per_cat = txns.group("categories.id").sum("entries.amount")

      budget = family.budgets.where(start_date: current_month).first_or_initialize
      budget.update!(
        end_date: current_month.end_of_month,
        currency: family.currency,
        budgeted_spending: spend_per_cat.values.sum / 3.0, # placeholder, refined below
        expected_income: 220_000
      )

      spend_per_cat.each do |cat_id, total|
        avg = total / 3.0
        rounded = ((avg / 500.0).round) * 500
        category = Category.find(cat_id)
        budget.budget_categories.find_or_create_by!(category: category) do |bc|
          bc.budgeted_spending = rounded
          bc.currency = family.currency
        end
      end

      # Update aggregate budgeted_spending to sum of categories
      budget.update!(budgeted_spending: budget.budget_categories.sum(:budgeted_spending))
    end

    def sync_family_accounts!(family)
      family.accounts.each do |account|
        sync = Sync.create!(syncable: account)
        sync.perform
      end
    end

    # Simple timing helper. Pass a descriptive label and a block; the runtime
    # will be printed automatically when the block completes.
    # If max_seconds is provided, raise RuntimeError when the block exceeds that
    # duration.  Useful to keep CI/dev machines honest about demo-data perf.
    def with_timing(label, max_seconds: nil)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      puts "⏱️  #{label} completed in #{duration.round(2)}s"

      if max_seconds && duration > max_seconds
        raise "Demo::Generator ##{label} exceeded #{max_seconds}s (#{duration.round(2)}s)"
      end

      result
    end

    # Override Kernel#rand so *all* `rand` calls inside this instance (including
    # those already present in the file) are routed through the seeded PRNG.
    def rand(*args)
      @rng.rand(*args)
    end

    # Adds a small random variation (±pct, default 3%) to +num+.  Useful for
    # making otherwise deterministic amounts look more natural while retaining
    # overall reproducibility via the seeded RNG.
    def jitter(num, pct = 0.03)
      variation = num * pct * (rand * 2 - 1) # rand(-pct..pct)
      (num + variation).round(2)
    end
end
