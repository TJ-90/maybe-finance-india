# How an investment account was last fed with data, used for stale-data reminders: when the last trade
# or import happened, which import to point the user at, and whether a monthly SIP stopped arriving.
class Account::FeedHistory
  SIP_MONTHS = 3
  # Buys in consecutive months count as one SIP when their days of the month are this close
  SIP_DAY_TOLERANCE = 5
  # Days after the usual SIP date before a missing buy is worth a reminder
  SIP_GRACE_DAYS = 3

  MissedSip = Data.define(:security, :expected_on)
  ImportLink = Data.define(:label, :path)

  attr_reader :account, :today

  def initialize(account, today: Date.current)
    @account = account
    @today = today
  end

  def last_trade_on
    account.entries.where(entryable_type: "Trade").maximum(:date)
  end

  def last_import
    return @last_import if defined?(@last_import)

    @last_import = Import.complete
                         .where(id: account.entries.where.not(import_id: nil).select(:import_id))
                         .or(Import.complete.where(account_id: account.id))
                         .order(created_at: :desc)
                         .first
  end

  # The newer of the last trade and the last completed import
  def last_fed_on
    [ last_trade_on, last_import&.updated_at&.to_date ].compact.max
  end

  def days_since_fed
    last_fed_on && (today - last_fed_on).to_i
  end

  def stale?(threshold_days)
    days = days_since_fed
    days.present? && days > threshold_days
  end

  # The import that matches how the account was last fed, so the reminder links to the right upload
  def import_link
    import = last_import

    case import
    when CasImport
      ImportLink.new("Upload your latest CAS", new_import_path(type: "CasImport"))
    when BrokerTradebookImport
      broker_link(import)
    else
      ImportLink.new("Upload your latest trades", new_import_path(type: "TradeImport"))
    end
  end

  # Securities bought every month for the last three months on about the same day, with no buy yet
  # this month although the usual day has passed
  def missed_sips
    return [] if today.day <= SIP_GRACE_DAYS

    buys_by_security.filter_map do |security, buys|
      expected_on = expected_sip_date(buys)
      next unless expected_on && today >= expected_on + SIP_GRACE_DAYS
      next if buys.any? { |date| date >= today.beginning_of_month }

      MissedSip.new(security: security, expected_on: expected_on)
    end
  end

  private
    def new_import_path(**params)
      Rails.application.routes.url_helpers.new_import_path(**params)
    end

    def broker_link(import)
      case import.broker_preset
      when "groww_mf_orders"
        ImportLink.new("Upload your Groww order history", new_import_path(type: "BrokerTradebookImport"))
      when "zerodha_console"
        ImportLink.new("Upload your Zerodha tradebook", new_import_path(type: "BrokerTradebookImport"))
      else
        ImportLink.new("Upload your latest trades", new_import_path(type: "BrokerTradebookImport"))
      end
    end

    # { security => [buy dates] } for the last few months, current month included
    def buys_by_security
      since = today.beginning_of_month << SIP_MONTHS

      rows = Trade.joins(:entry)
                  .where(entries: { account_id: account.id })
                  .where("trades.qty > 0")
                  .where("entries.date >= ?", since)
                  .pluck(:security_id, "entries.date")

      securities = Security.where(id: rows.map(&:first).uniq).index_by(&:id)
      rows.group_by(&:first).to_h { |security_id, group| [ securities[security_id], group.map(&:last) ] }
    end

    # This month's SIP date when each of the previous three months has a buy and the days of the
    # month are close together; nil when the buys don't look like a SIP.
    def expected_sip_date(buys)
      days = (1..SIP_MONTHS).map do |back|
        month_start = today.beginning_of_month << back
        in_month = buys.select { |date| date >= month_start && date <= month_start.end_of_month }
        return nil if in_month.empty?

        in_month.min.day
      end

      return nil if days.max - days.min > SIP_DAY_TOLERANCE

      day = days.sort[days.size / 2]
      Date.new(today.year, today.month, [ day, today.end_of_month.day ].min)
    end
end
