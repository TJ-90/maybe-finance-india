require "test_helper"

class RefreshInvestmentValuesJobTest < ActiveJob::TestCase
  include TaxTestHelper

  setup do
    @family = inr_family
    @held = create_investment_account(@family, name: "Held")
    @other = create_investment_account(@family, name: "Other")
    @sold_out = create_investment_account(@family, name: "Sold out")

    @fund = create_tax_security("FUNDA")
    @unrelated = create_tax_security("FUNDB")

    create_folio_trade @held, @fund, qty: 10, price: 100, date: 30.days.ago.to_date
    create_folio_trade @other, @unrelated, qty: 10, price: 100, date: 30.days.ago.to_date
    create_folio_trade @sold_out, @fund, qty: 10, price: 100, date: 30.days.ago.to_date
    create_folio_trade @sold_out, @fund, qty: -10, price: 110, date: 10.days.ago.to_date

    Sync.delete_all
    @started_at = Time.current
  end

  test "syncs accounts holding a security whose price changed, once each" do
    set_price(@fund, 120)

    assert_difference -> { Sync.count }, 1 do
      assert_equal 1, RefreshInvestmentValuesJob.perform_now(since: @started_at.iso8601(6))
    end

    assert_equal 1, @held.syncs.count
    assert_equal Date.current, @held.syncs.first.window_start_date
    assert_equal 0, @other.syncs.count
    assert_equal 0, @sold_out.syncs.count
  end

  test "is idempotent: an account with a sync already pending is not synced again" do
    set_price(@fund, 120)

    2.times { RefreshInvestmentValuesJob.perform_now(since: @started_at.iso8601(6)) }

    assert_equal 1, @held.syncs.count
  end

  test "ignores prices written before the import started" do
    set_price(@fund, 120)

    assert_no_difference -> { Sync.count } do
      RefreshInvestmentValuesJob.perform_now(since: 1.minute.from_now.iso8601(6))
    end
  end

  test "ignores offline securities" do
    @fund.update!(offline: true)
    set_price(@fund, 120)

    assert_no_difference -> { Sync.count } do
      RefreshInvestmentValuesJob.perform_now(since: @started_at.iso8601(6))
    end
  end

  test "syncs accounts in a foreign currency after their exchange rate changed" do
    usd = @family.accounts.create!(name: "US brokerage", balance: 0, cash_balance: 0, currency: "USD", accountable: Investment.new)
    inr_only = @held
    ExchangeRate.create!(from_currency: "USD", to_currency: "INR", date: Date.current, rate: 84)

    RefreshInvestmentValuesJob.perform_now(since: @started_at.iso8601(6))

    assert_equal 1, usd.syncs.count
    assert_equal 0, inr_only.syncs.count
  end

  test "an account in both groups is synced once with the earliest window" do
    usd = @family.accounts.create!(name: "US brokerage", balance: 0, cash_balance: 0, currency: "USD", accountable: Investment.new)
    us_stock = Security.create!(ticker: "AAPLX", exchange_operating_mic: "XNAS", name: "Apple")
    usd.entries.create!(name: "Buy", date: 5.days.ago.to_date, amount: 100, currency: "USD", entryable: Trade.new(qty: 1, price: 100, currency: "USD", security: us_stock))
    Sync.delete_all

    Security::Price.create!(security: us_stock, date: Date.current, price: 100, currency: "USD")
    ExchangeRate.create!(from_currency: "USD", to_currency: "INR", date: 3.days.ago.to_date, rate: 84)

    RefreshInvestmentValuesJob.perform_now(since: @started_at.iso8601(6))
    assert_equal 3.days.ago.to_date, usd.syncs.first.window_start_date
  end
end
