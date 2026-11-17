require "test_helper"
require Rails.root.join("db/migrate/20261117120001_add_tracks_cash_to_investments")

# Investment accounts that hold no cash (mutual funds, NPS, ULIP, imported order histories): trades do not
# move cash, cash stays 0 and the balance is the value of the holdings.
class HoldingsOnlyAccountTest < ActiveSupport::TestCase
  include LedgerTestingHelper

  setup do
    @family = families(:empty)
    @today = Date.current
  end

  test "subtypes without cash default to holdings-only, cash-capable subtypes track cash" do
    %w[mutual_fund nps_tier1 nps_tier2 ulip].each do |subtype|
      account = create_investment(subtype: subtype)
      assert account.holdings_only?, "#{subtype} should be holdings-only"
      assert_equal 0, account.cash_balance
    end

    %w[demat brokerage pms_aif angel].each do |subtype|
      assert_not create_investment(subtype: subtype).holdings_only?, "#{subtype} should track cash"
    end
  end

  test "an explicit choice is kept for cash-capable subtypes" do
    assert create_investment(subtype: "demat", tracks_cash: false).holdings_only?
  end

  test "buys and sells keep cash at 0 and the balance equals the holdings value" do
    account = create_investment(subtype: "mutual_fund")
    fund = Security.create!(ticker: "900901", name: "Sample Fund", exchange_operating_mic: Security::AMFI_MIC, kind: "mutual_fund")

    [ [ 10.days.ago.to_date, 100 ], [ 5.days.ago.to_date, 110 ], [ @today, 120 ] ].each do |date, price|
      Security::Price.create!(security: fund, date: date, price: price, currency: "INR")
    end
    # 10 units bought at 100, 5 more at 110, 4 redeemed at 115 on the last day
    add_trade(account, fund, 10.days.ago.to_date, 10, 100)
    add_trade(account, fund, 5.days.ago.to_date, 5, 110)
    add_trade(account, fund, @today, -4, 115)

    Balance::Materializer.new(account, strategy: :forward).materialize_balances
    account.reload

    last = account.balances.order(:date).last
    assert_equal 0, last.end_cash_balance
    assert_equal 0, account.cash_balance
    # 11 units left at 120
    assert_equal 1320, last.end_balance
    assert_equal 1320, account.balance
    assert account.balances.all? { |balance| balance.end_cash_balance.zero? }, "cash must be 0 on every day"
    assert_equal account.holdings.where(date: @today).sum(:amount), account.balance
  end

  test "an account that tracks cash still treats buys as cash going out" do
    account = create_account_with_ledger(
      account: { type: Investment, currency: "INR" },
      entries: [
        { type: "opening_anchor", date: 3.days.ago.to_date, balance: 5000 },
        { type: "trade", date: 1.day.ago.to_date, ticker: "AAPL", qty: 10, price: 100 }
      ],
      holdings: [ { date: 1.day.ago.to_date, ticker: "AAPL", qty: 10, price: 100, amount: 1000 } ]
    )

    assert_not account.holdings_only?
    last = Balance::ForwardCalculator.new(account).calculate.last
    assert_equal 4000, last.cash_balance
    assert_equal 5000, last.balance
  end

  test "forward calculator derives no cash for buys and sells on a holdings-only account" do
    account = create_account_with_ledger(
      account: { type: Investment, currency: "INR" },
      entries: [
        { type: "opening_anchor", date: 3.days.ago.to_date, balance: 0 },
        { type: "trade", date: 2.days.ago.to_date, ticker: "FUNDX", qty: 10, price: 100 },
        { type: "trade", date: 1.day.ago.to_date, ticker: "FUNDX", qty: -4, price: 100 }
      ],
      holdings: [
        { date: 2.days.ago.to_date, ticker: "FUNDX", qty: 10, price: 100, amount: 1000 },
        { date: 1.day.ago.to_date, ticker: "FUNDX", qty: 6, price: 100, amount: 600 }
      ]
    )
    account.accountable.update!(tracks_cash: false)

    calculated = Balance::ForwardCalculator.new(account.reload).calculate

    assert calculated.all? { |balance| balance.cash_balance.zero? }
    assert_equal 600, calculated.last.balance
    assert_equal 1000, calculated.find { |b| b.date == 2.days.ago.to_date }.balance
  end

  test "holding weights add up to 100 percent of the holdings value" do
    account = create_investment(subtype: "mutual_fund")
    a = Security.create!(ticker: "900902", name: "Fund A", exchange_operating_mic: Security::AMFI_MIC)
    b = Security.create!(ticker: "900903", name: "Fund B", exchange_operating_mic: Security::AMFI_MIC)
    account.holdings.create!(security: a, date: @today, qty: 10, price: 300, amount: 3000, currency: "INR")
    account.holdings.create!(security: b, date: @today, qty: 10, price: 100, amount: 1000, currency: "INR")
    account.update!(balance: 4000, cash_balance: 0)

    weights = account.holdings.map(&:weight)

    assert_in_delta 100, weights.sum, 0.001
    assert_in_delta 75, account.holdings.find_by(security: a).weight, 0.001
  end

  test "the backfill turns tracking off for existing cash-less subtypes only" do
    mf = create_investment(subtype: "mutual_fund")
    nps = create_investment(subtype: "nps_tier1")
    demat = create_investment(subtype: "demat")
    [ mf, nps ].each { |account| account.accountable.update_columns(tracks_cash: true) } # as before the migration

    ActiveRecord::Migration.suppress_messages { AddTracksCashToInvestments.new.backfill }

    assert_not mf.reload.accountable.tracks_cash?
    assert_not nps.reload.accountable.tracks_cash?
    assert demat.reload.accountable.tracks_cash?
  end

  test "new accounts made by the importers are holdings-only" do
    cas = CasImport.new(family: @family).create_investor_account!("Asha Sample")
    assert cas.holdings_only?
    assert_equal 0, cas.cash_balance

    trade = TradeImport.new(family: @family).create_investor_account!("Tradebook account")
    assert trade.holdings_only?

    groww = BrokerTradebookImport.new(family: @family, broker_preset: "groww_mf_orders").create_investor_account!("Groww orders")
    assert groww.holdings_only?
    assert_equal "mutual_fund", groww.subtype

    zerodha = BrokerTradebookImport.new(family: @family, broker_preset: "zerodha_console").create_investor_account!("Zerodha")
    assert zerodha.holdings_only?
    assert_equal "demat", zerodha.subtype
  end

  private
    def create_investment(subtype:, tracks_cash: nil)
      investment = tracks_cash.nil? ? Investment.new : Investment.new(tracks_cash: tracks_cash)
      @family.accounts.create!(name: "Test #{subtype} #{SecureRandom.hex(3)}", accountable: investment, subtype: subtype, balance: 0, cash_balance: 0, currency: "INR")
    end

    def add_trade(account, security, date, qty, price)
      account.entries.create!(
        name: "Trade", date: date, amount: qty * price, currency: "INR",
        entryable: Trade.new(qty: qty, security: security, price: price, currency: "INR")
      )
    end
end
