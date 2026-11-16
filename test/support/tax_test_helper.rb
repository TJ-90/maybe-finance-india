module TaxTestHelper
  def inr_family
    families(:dylan_family).tap { |family| family.update!(currency: "INR", country: "IN") }
  end

  def create_investment_account(family, name: "Demat")
    family.accounts.create!(name: name, balance: 0, cash_balance: 0, currency: "INR", accountable: Investment.new)
  end

  def create_tax_security(ticker, tax_category: "equity", kind: "mutual_fund")
    Security.create!(ticker: ticker, name: "#{ticker} Fund", exchange_operating_mic: "XNSE", kind: kind, tax_category: tax_category, asset_class: "equity")
  end

  # qty > 0 buys, qty < 0 sells. Amount follows the app's convention: buys positive, sells negative.
  def create_folio_trade(account, security, qty:, price:, date:, folio: nil)
    account.entries.create!(
      name: "#{qty.positive? ? 'Buy' : 'Sell'} #{security.ticker}",
      date: date,
      amount: qty * price,
      currency: "INR",
      entryable: Trade.new(qty: qty, price: price, currency: "INR", security: security, folio_number: folio)
    )
  end

  def set_price(security, price, date: Date.current)
    Security::Price.create!(security: security, date: date, price: price, currency: "INR")
  end
end
