require "test_helper"

class Notification::RemindersTest < ActiveSupport::TestCase
  include TaxTestHelper

  setup do
    @user = users(:family_admin)
    @family = inr_family
    @today = Date.new(2026, 11, 16)
    @account = create_investment_account(@family)
    @fund = create_tax_security("REMFUND")
  end

  def reminders(today: @today)
    Notification::Reminders.new(@user, today: today)
  end

  def notifications(kind)
    @user.notifications.where(kind: kind)
  end

  def complete_import(type, updated_at:, preset: nil)
    import = @family.imports.create!(type: type, account: @account, status: "complete")
    import.update!(broker_preset: preset) if preset
    import.update_columns(updated_at: updated_at)
    import
  end

  # --- stale accounts ---

  test "an account with no recent trades gets a reminder linking to the generic trade import" do
    create_folio_trade(@account, @fund, qty: 10, price: 100, date: @today - 60)

    assert_difference -> { notifications("stale_account").count }, 1 do
      reminders.stale_accounts
    end

    notification = notifications("stale_account").first
    assert_equal "#{@account.name} needs an update", notification.title
    assert_equal "/imports/new?type=TradeImport", notification.url
    assert_match(/60 days/, notification.body)
    assert_equal "stale_account:#{@account.id}:2026-11", notification.dedupe_key
  end

  test "a recent trade means no reminder" do
    create_folio_trade(@account, @fund, qty: 10, price: 100, date: @today - 34)

    assert_no_difference -> { notifications("stale_account").count } do
      reminders.stale_accounts
    end
  end

  test "the threshold is per user" do
    create_folio_trade(@account, @fund, qty: 10, price: 100, date: @today - 40)
    NotificationPreference.create!(user: @user, stale_data_days: 60)

    assert_no_difference -> { notifications("stale_account").count } do
      reminders.stale_accounts
    end

    NotificationPreference.for(@user).update!(stale_data_days: 30)
    assert_difference -> { notifications("stale_account").count }, 1 do
      reminders.stale_accounts
    end
  end

  test "an account that was never fed is left alone" do
    assert_no_difference -> { Notification.count } do
      reminders.stale_accounts
    end
  end

  test "the reminder is only raised once a month" do
    create_folio_trade(@account, @fund, qty: 10, price: 100, date: @today - 60)
    reminders.stale_accounts

    assert_no_difference -> { notifications("stale_account").count } do
      reminders.stale_accounts
      reminders(today: @today + 10).stale_accounts
    end

    assert_difference -> { notifications("stale_account").count }, 1 do
      reminders(today: Date.new(2026, 12, 2)).stale_accounts
    end
  end

  test "can be switched off" do
    create_folio_trade(@account, @fund, qty: 10, price: 100, date: @today - 60)
    NotificationPreference.create!(user: @user, disabled_kinds: [ "stale_account" ])

    assert_no_difference -> { Notification.count } do
      reminders.stale_accounts
    end
  end

  test "links to the CAS upload when the account was last fed by a CAS" do
    complete_import("CasImport", updated_at: @today.to_time - 50.days)

    reminders.stale_accounts

    notification = notifications("stale_account").first
    assert_equal "/imports/new?type=CasImport", notification.url
    assert_match(/Upload your latest CAS/, notification.body)
  end

  test "links to Groww for a Groww order history import" do
    complete_import("BrokerTradebookImport", updated_at: @today.to_time - 50.days, preset: "groww_mf_orders")

    reminders.stale_accounts

    assert_match(/Upload your Groww order history/, notifications("stale_account").first.body)
    assert_equal "/imports/new?type=BrokerTradebookImport", notifications("stale_account").first.url
  end

  test "links to the Zerodha tradebook for a Zerodha import" do
    complete_import("BrokerTradebookImport", updated_at: @today.to_time - 50.days, preset: "zerodha_console")

    reminders.stale_accounts

    assert_match(/Upload your Zerodha tradebook/, notifications("stale_account").first.body)
  end

  test "the latest import decides the link" do
    complete_import("CasImport", updated_at: @today.to_time - 90.days)
    complete_import("TradeImport", updated_at: @today.to_time - 50.days)

    reminders.stale_accounts

    assert_equal "/imports/new?type=TradeImport", notifications("stale_account").first.url
  end

  test "a recent import counts even when its trades are old" do
    create_folio_trade(@account, @fund, qty: 10, price: 100, date: @today - 400)
    complete_import("CasImport", updated_at: @today.to_time - 3.days)

    assert_no_difference -> { Notification.count } do
      reminders.stale_accounts
    end
  end

  # --- SIP detection ---

  test "a monthly SIP that did not arrive this month triggers the reminder early" do
    [ Date.new(2026, 8, 8), Date.new(2026, 9, 9), Date.new(2026, 10, 10) ].each do |date|
      create_folio_trade(@account, @fund, qty: 5, price: 100, date: date)
    end
    NotificationPreference.create!(user: @user, stale_data_days: 90)

    reminders.stale_accounts

    notification = notifications("stale_account").first
    assert_equal "Expected SIP missing in #{@account.name}", notification.title
    assert_match(/REMFUND Fund/, notification.body)
    assert_match(/9th/, notification.body)
  end

  test "no SIP reminder when this month's SIP arrived, before the grace period, or when the pattern is irregular" do
    [ Date.new(2026, 8, 8), Date.new(2026, 9, 9), Date.new(2026, 10, 10) ].each do |date|
      create_folio_trade(@account, @fund, qty: 5, price: 100, date: date)
    end
    NotificationPreference.create!(user: @user, stale_data_days: 90)

    assert_empty Account::FeedHistory.new(@account, today: Date.new(2026, 11, 11)).missed_sips

    create_folio_trade(@account, @fund, qty: 5, price: 100, date: Date.new(2026, 11, 9))
    assert_empty Account::FeedHistory.new(@account, today: @today).missed_sips

    other = create_investment_account(@family, name: "Irregular")
    [ Date.new(2026, 8, 2), Date.new(2026, 9, 20), Date.new(2026, 10, 10) ].each do |date|
      create_folio_trade(other, @fund, qty: 5, price: 100, date: date)
    end
    assert_empty Account::FeedHistory.new(other, today: @today).missed_sips
  end

  # --- stale NAVs ---

  def hold(security)
    @account.holdings.create!(security: security, date: @today, qty: 10, price: 10, amount: 100, currency: "INR")
  end

  test "stale NAVs for a held fund point at the NAVAll upload" do
    hold(@fund)
    set_price(@fund, 10, date: @today - 5)

    assert_difference -> { notifications("stale_navs").count }, 1 do
      reminders.stale_navs
      reminders.stale_navs
    end

    notification = notifications("stale_navs").first
    assert_equal "/settings/market_data", notification.url
    assert_match(/NAVAll\.txt/, notification.body)
  end

  test "fresh NAVs, no held funds and the opt-out all stay quiet" do
    reminders.stale_navs
    assert_equal 0, notifications("stale_navs").count

    hold(@fund)
    set_price(@fund, 10, date: @today - 3)
    reminders.stale_navs
    assert_equal 0, notifications("stale_navs").count

    Security::Price.delete_all
    NotificationPreference.create!(user: @user, disabled_kinds: [ "stale_navs" ])
    reminders.stale_navs
    assert_equal 0, notifications("stale_navs").count
  end

  test "a held fund with no price at all counts as stale" do
    hold(@fund)

    assert_difference -> { notifications("stale_navs").count }, 1 do
      reminders.stale_navs
    end
  end

  # --- insurance premiums ---

  test "premiums due within 7 days are reminded once" do
    policy = insurance_policies(:term)
    policy.update!(next_premium_due_on: Date.current + 5)

    assert_difference -> { notifications("premium_due").count }, 1 do
      Notification::Reminders.new(@user).premium_due
      Notification::Reminders.new(@user).premium_due
    end

    notification = notifications("premium_due").first
    assert_match(/Example Life Insurance term life premium is due in 5 days/, notification.title)
    assert_match(/Premium/, notification.detail)
    assert_no_match(/\d{2},\d{3}|₹/, notification.body.to_s + notification.title)
    assert_equal "premium_due:#{policy.id}:#{policy.next_premium_due_on.iso8601}", notification.dedupe_key
  end

  test "premiums further out are not reminded, and the next cycle is a new reminder" do
    policy = insurance_policies(:term)
    policy.update!(next_premium_due_on: Date.current + 8)
    Notification::Reminders.new(@user).premium_due
    assert_equal 0, notifications("premium_due").count

    policy.update!(next_premium_due_on: Date.current + 2)
    Notification::Reminders.new(@user).premium_due
    policy.update!(next_premium_due_on: Date.current + 3)
    Notification::Reminders.new(@user).premium_due
    assert_equal 2, notifications("premium_due").count
  end

  # --- March tax reminder ---

  def long_term_gain_setup
    create_folio_trade(@account, @fund, qty: 100, price: 100, date: Date.new(2025, 1, 10), folio: "F1")
    set_price(@fund, 200, date: Date.new(2027, 3, 10))
  end

  test "in March a harvestable long-term gain triggers the tax reminder, once" do
    long_term_gain_setup
    march = Date.new(2027, 3, 10)

    travel_to march do
      assert_difference -> { notifications("tax_year_end").count }, 1 do
        reminders(today: march).tax_year_end
        reminders(today: march + 5).tax_year_end
      end
    end

    notification = notifications("tax_year_end").first
    assert_equal "Review tax harvesting before 31 March", notification.title
    assert_equal "/tax_center", notification.url
    assert_equal "tax_year_end:2026", notification.dedupe_key
    assert_match(/₹/, notification.detail)
    assert_no_match(/₹/, notification.body)
  end

  test "no tax reminder outside March" do
    long_term_gain_setup

    assert_no_difference -> { Notification.count } do
      reminders(today: Date.new(2027, 2, 28)).tax_year_end
      reminders(today: Date.new(2027, 4, 1)).tax_year_end
    end
  end

  test "no tax reminder when nothing is worth harvesting" do
    create_folio_trade(@account, @fund, qty: 100, price: 100, date: Date.new(2025, 1, 10), folio: "F1")
    set_price(@fund, 100.5, date: Date.new(2027, 3, 10)) # gain of 50

    travel_to Date.new(2027, 3, 10) do
      assert_no_difference -> { Notification.count } do
        reminders(today: Date.new(2027, 3, 10)).tax_year_end
      end
    end
  end

  test "no tax reminder when the exemption is already used up" do
    long_term_gain_setup
    seller = create_tax_security("USEDUP")
    create_folio_trade(@account, seller, qty: 1000, price: 100, date: Date.new(2024, 1, 10), folio: "F2")
    create_folio_trade(@account, seller, qty: -1000, price: 400, date: Date.new(2026, 12, 10), folio: "F2")

    travel_to Date.new(2027, 3, 10) do
      assert_no_difference -> { Notification.count } do
        reminders(today: Date.new(2027, 3, 10)).tax_year_end
      end
    end
  end

  test "run! runs every reminder and survives a failing one" do
    create_folio_trade(@account, @fund, qty: 10, price: 100, date: @today - 60)
    reminders_runner = reminders
    reminders_runner.stubs(:stale_navs).raises("boom")

    assert_difference -> { notifications("stale_account").count }, 1 do
      reminders_runner.run!
    end
  end

  test "the reminders job runs for every active user" do
    create_folio_trade(@account, @fund, qty: 10, price: 100, date: @today - 60)

    SendRemindersJob.perform_now(date: @today)

    assert_equal 1, users(:family_admin).notifications.where(kind: "stale_account").count
    assert_equal 1, users(:family_member).notifications.where(kind: "stale_account").count
  end
end
