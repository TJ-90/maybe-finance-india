require "test_helper"

class TradeTest < ActiveSupport::TestCase
  test "build_name generates buy trade name" do
    name = Trade.build_name("buy", 10, "AAPL")
    assert_equal "Buy 10.0 shares of AAPL", name
  end

  test "build_name generates sell trade name" do
    name = Trade.build_name("sell", 5, "MSFT")
    assert_equal "Sell 5.0 shares of MSFT", name
  end

  test "build_name handles absolute value for negative quantities" do
    name = Trade.build_name("sell", -5, "GOOGL")
    assert_equal "Sell 5.0 shares of GOOGL", name
  end

  test "build_name handles decimal quantities" do
    name = Trade.build_name("buy", 0.25, "BTC")
    assert_equal "Buy 0.25 shares of BTC", name
  end

  test "build_name names a mutual fund after the fund, in units" do
    fund = Security.new(ticker: "900003", name: "Sample Liquid Fund - Direct Plan - Growth", exchange_operating_mic: Security::AMFI_MIC, kind: "mutual_fund")

    assert_equal "Buy 3.368 units of Sample Liquid Fund - Direct Plan - Growth", Trade.build_name("buy", 3.368, fund)
    assert_equal "Sell 2.0 units of Sample Liquid Fund - Direct Plan - Growth", Trade.build_name("sell", -2, fund)
  end

  test "build_name keeps shares for a stock security" do
    stock = Security.new(ticker: "RELIANCE", name: "Reliance Industries Ltd", exchange_operating_mic: "XNSE", kind: "stock")

    assert_equal "Buy 10.0 shares of RELIANCE", Trade.build_name("buy", 10, stock)
  end

  test "build_name falls back to the scheme name when a fund security has no name" do
    MutualFundScheme.create!(scheme_code: "900077", name: "Scheme Name Fund", plan: "direct", option: "growth")
    fund = Security.new(ticker: "900077", exchange_operating_mic: Security::AMFI_MIC)

    assert_equal "Buy 1.0 units of Scheme Name Fund", Trade.build_name("buy", 1, fund)
  end

  test "rename_auto_named! fixes only names that match an old generated pattern" do
    family = families(:dylan_family)
    account = family.accounts.create!(name: "Demat", balance: 0, cash_balance: 0, currency: "INR", accountable: Investment.new)
    fund = Security.create!(ticker: "900003", name: "Sample Liquid Fund", exchange_operating_mic: Security::AMFI_MIC, kind: "mutual_fund", isin: "INF9D0003010")
    stock = Security.create!(ticker: "RELIANCE", name: "Reliance", exchange_operating_mic: "XNSE", kind: "stock")

    named = lambda do |security, qty, name|
      account.entries.create!(name: name, date: Date.current, amount: qty * 10, currency: "INR",
                              entryable: Trade.new(qty: qty, price: 10, currency: "INR", security: security))
    end

    demo = named.call(fund, 3.368, "Buy 3.368 900003")
    form = named.call(fund, -2, "Sell 2.0 shares of 900003")
    broker = named.call(fund, 5, "Buy INF9D0003010")
    whole = named.call(stock, 10, "Buy 10 RELIANCE")
    custom = named.call(fund, 4, "My SIP instalment")
    similar = named.call(fund, 4, "Buy 4.0 900003 (corrected)")
    current = named.call(fund, 1, "Buy 1.0 units of Sample Liquid Fund")
    other_qty = named.call(fund, 6, "Buy 7.0 900003")

    assert_equal 4, Trade.rename_auto_named!

    assert_equal "Buy 3.368 units of Sample Liquid Fund", demo.reload.name
    assert_equal "Sell 2.0 units of Sample Liquid Fund", form.reload.name
    assert_equal "Buy 5.0 units of Sample Liquid Fund", broker.reload.name
    assert_equal "Buy 10.0 shares of RELIANCE", whole.reload.name
    assert_equal "My SIP instalment", custom.reload.name
    assert_equal "Buy 4.0 900003 (corrected)", similar.reload.name
    assert_equal "Buy 1.0 units of Sample Liquid Fund", current.reload.name
    assert_equal "Buy 7.0 900003", other_qty.reload.name

    assert_equal 0, Trade.rename_auto_named!
  end
end
