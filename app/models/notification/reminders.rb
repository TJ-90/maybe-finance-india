# The reminders one user can receive besides goal alerts: stale investment data, stale NAVs, insurance
# premiums falling due and the March tax review. Every reminder has a dedupe key, so running this
# every day only ever raises each reminder once per window.
class Notification::Reminders
  NAV_STALE_AFTER_DAYS = 3
  PREMIUM_WINDOW_DAYS = 7
  # Harvestable long-term gain below which the March tax reminder isn't worth a notification
  MIN_WORTHWHILE_LTCG = 1000

  attr_reader :user, :today

  def initialize(user, today: Date.current)
    @user = user
    @today = today
  end

  def run!
    %i[stale_accounts stale_navs premium_due tax_year_end].each do |trigger|
      send(trigger)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { reminder: trigger, user_id: user.id })
    end
  end

  def stale_accounts
    threshold = preferences.stale_data_days

    family.accounts_with_investments.each do |account|
      feed = Account::FeedHistory.new(account, today: today)
      key = "stale_account:#{account.id}:#{today.strftime("%Y-%m")}"
      link = feed.import_link

      if feed.stale?(threshold)
        notify("stale_account", key, "#{account.name} needs an update",
               "No new trades or imports for #{feed.days_since_fed} days. #{link.label} to keep returns and tax estimates accurate.", link.path)
      elsif (missed = feed.missed_sips).any?
        names = missed.map { |sip| sip.security.display_name }.to_sentence
        notify("stale_account", key, "Expected SIP missing in #{account.name}",
               "No purchase of #{names} this month, although one usually arrives around the #{missed.first.expected_on.day.ordinalize}. #{link.label} if it went through.", link.path)
      end
    end
  end

  def stale_navs
    securities = held_mutual_funds
    return if securities.empty?

    latest = Security::Price.where(security_id: securities.map(&:id)).group(:security_id).maximum(:date)
    stale = securities.select { |security| latest[security.id].nil? || (today - latest[security.id]).to_i > NAV_STALE_AFTER_DAYS }
    return if stale.empty?

    notify("stale_navs", "stale_navs:#{today.strftime("%G-W%V")}", "Mutual fund NAVs are out of date",
           "#{stale.size} of your #{"fund".pluralize(securities.size)} haven't had a new NAV for more than #{NAV_STALE_AFTER_DAYS} days. If the market data source is failing, upload NAVAll.txt in Settings, Market data.",
           url_helpers.settings_market_data_path)
  end

  def premium_due
    family.insurance_policies.premium_due_within(PREMIUM_WINDOW_DAYS.days).each do |policy|
      days = policy.days_until_premium(today)
      due_text = days.zero? ? "today" : "in #{days} #{"day".pluralize(days)}"

      notify("premium_due", "premium_due:#{policy.id}:#{policy.next_premium_due_on.iso8601}",
             "#{policy.insurer} #{policy.kind_label.downcase} premium is due #{due_text}",
             "Due on #{policy.next_premium_due_on.strftime("%d %b %Y")}.", url_helpers.insurance_policies_path,
             detail: (policy.premium_money ? "Premium #{policy.premium_money.format_compact}" : nil))
    end
  end

  # 1-31 March: remind when unused LTCG exemption and long-term gains are both available
  def tax_year_end
    return unless today.month == 3

    harvester = tax_harvester
    return unless harvester.exemption_remaining.positive? && harvester.recommended_ltcg >= MIN_WORTHWHILE_LTCG

    money = ->(amount) { Money.new(amount, family.currency).format_compact }
    notify("tax_year_end", "tax_year_end:#{Period.financial_year_start(today).year}", "Review tax harvesting before 31 March",
           "You may still have unused long-term capital gains exemption this financial year.", url_helpers.tax_center_path,
           detail: "Up to #{money.call(harvester.recommended_ltcg)} of long-term gains can be booked within the #{money.call(harvester.exemption_remaining)} exemption left.")
  end

  private
    def family
      user.family
    end

    def preferences
      @preferences ||= NotificationPreference.for(user)
    end

    def notify(kind, key, title, body, url, detail: nil)
      Notification.notify(user: user, kind: kind, title: title, body: body, detail: detail, url: url, dedupe_key: key)
    end

    def held_mutual_funds
      family.accounts_with_investments.flat_map { |account| account.current_holdings.includes(:security).map(&:security) }
            .uniq.select(&:kind_mutual_fund?)
    end

    # Per account set, since household members don't have their own accounts yet: every investment account
    def tax_harvester
      accounts = family.accounts_with_investments.to_a
      report = TaxCenter::Report.new(family: family, accounts: accounts, financial_year_start: Period.financial_year_start(today))
      TaxCenter::Harvester.new(family: family, report: report, date: today)
    end

    def url_helpers
      Rails.application.routes.url_helpers
    end
end
