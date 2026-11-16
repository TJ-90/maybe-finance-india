namespace :demo_data do
  desc "Load empty demo dataset (no financial data)"
  task empty: :environment do
    start = Time.now
    puts "🚀 Loading EMPTY demo data…"

    Demo::Generator.new.generate_empty_data!

    puts "✅ Done in #{(Time.now - start).round(2)}s"
  end

  desc "Load new-user demo dataset (family created but not onboarded)"
  task new_user: :environment do
    start = Time.now
    puts "🚀 Loading NEW-USER demo data…"

    Demo::Generator.new.generate_new_user_data!

    puts "✅ Done in #{(Time.now - start).round(2)}s"
  end

  desc "Load full realistic demo dataset"
  task default: :environment do
    start    = Time.now
    seed     = ENV.fetch("SEED", Random.new_seed)
    puts "🚀 Loading FULL demo data (seed=#{seed})…"

    generator = Demo::Generator.new(seed: seed)
    generator.generate_default_data!

    validate_demo_data

    elapsed = Time.now - start
    puts "🎉 Demo data ready in #{elapsed.round(2)}s"
  end

  # ---------------------------------------------------------------------------
  # Validation helpers
  # ---------------------------------------------------------------------------
  def validate_demo_data
    total_entries   = Entry.count
    trade_entries   = Entry.where(entryable_type: "Trade").count
    categorized_txn = Transaction.joins(:category).count
    txn_total       = Transaction.count
    family          = Family.joins(:users).find_by(users: { email: ENV.fetch("DEMO_EMAIL", "user@example.com") })

    coverage = ((categorized_txn.to_f / txn_total) * 100).round(1)

    puts "\n📊 Validation Summary".ljust(40, "-")
    puts "Entries total:              #{total_entries}"
    puts "Trade entries:             #{trade_entries}"
    puts "Txn categorization:        #{coverage}% (>=25% ✅, transfers and SIP debits are uncategorized by design)"

    if family
      puts "Net worth:                  #{family.balance_sheet.net_worth_money.format}"
      puts "Portfolio XIRR:             #{((family.investment_summary.xirr || 0) * 100).round(1)}%"
      puts "Goals / insurance policies: #{family.goals.count} / #{family.insurance_policies.count}"
    end

    puts "Total entries #{total_entries} outside 1k–3k range" unless total_entries.between?(1_000, 3_000)
    puts "Trade entries #{trade_entries} outside 50–300 range" unless trade_entries.between?(50, 300)
    puts "Categorization coverage below 25%" unless coverage >= 25
  end
end
