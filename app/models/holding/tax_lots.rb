# Replays an account's trades first-in-first-out, per (account, security, folio number), to produce
#
# - open lots: what is still held, with buy date and cost per unit
# - realized lots: the buy lots consumed by each sale, with cost, proceeds and holding period
# - redemptions: one row per sell trade with the net gain, as in CAMS/KFintech capital gains statements
#
# A switch-out is recorded as a sell trade (plus a buy in the target fund), so it is a redemption here too.
# All amounts are in `currency` (the family currency by default); trade prices in other currencies are
# converted at the trade date, falling back to 1:1 when no rate is available.
class Holding::TaxLots
  Lot = Struct.new(:account, :security, :folio, :buy_date, :qty, :cost_per_unit, keyword_init: true) do
    def cost
      qty * cost_per_unit
    end

    def group_key
      [ account.id, security.id, folio.to_s ]
    end

    def split(units)
      [
        self.class.new(**to_h, qty: units),
        self.class.new(**to_h, qty: qty - units)
      ]
    end
  end

  RealizedLot = Struct.new(:account, :security, :folio, :entry, :buy_date, :sell_date, :qty, :cost, :proceeds, keyword_init: true) do
    def gain
      proceeds - cost
    end

    def holding_days
      (sell_date - buy_date).to_i
    end
  end

  Redemption = Struct.new(:account, :security, :folio, :entry, :date, :lots, keyword_init: true) do
    def qty
      lots.sum(&:qty)
    end

    def cost
      lots.sum(&:cost)
    end

    def proceeds
      lots.sum(&:proceeds)
    end

    def gain
      proceeds - cost
    end
  end

  attr_reader :open_lots, :realized_lots, :redemptions, :unmatched_sales

  def initialize(accounts, currency: nil, as_of: nil)
    @accounts = Array(accounts)
    @currency = currency
    @as_of = as_of
    @open_lots = []
    @realized_lots = []
    @redemptions = []
    @unmatched_sales = []
    replay
  end

  def open_lots_by_group
    open_lots.group_by(&:group_key)
  end

  def realized_between(start_date, end_date)
    realized_lots.select { |lot| lot.sell_date.between?(start_date, end_date) }
  end

  def redemptions_between(start_date, end_date)
    redemptions.select { |redemption| redemption.date.between?(start_date, end_date) }
  end

  private
    attr_reader :accounts, :as_of

    def target_currency
      @currency
    end

    def trade_entries
      scope = Entry.where(account_id: accounts.map(&:id), entryable_type: "Trade").includes(:entryable, :account)
      scope = scope.where("entries.date <= ?", as_of) if as_of
      # Buys before sells on the same day, so same-day round trips don't look oversold
      scope.to_a.sort_by { |entry| [ entry.date, entry.entryable.qty.positive? ? 0 : 1, entry.created_at ] }
    end

    def replay
      queues = Hash.new { |hash, key| hash[key] = [] }

      trade_entries.each do |entry|
        trade = entry.entryable
        account = entry.account
        folio = trade.folio_number.to_s
        key = [ account.id, trade.security_id, folio ]
        price = unit_price(trade, entry.date, account)

        if trade.qty.positive?
          queues[key] << Lot.new(account: account, security: trade.security, folio: trade.folio_number,
                                 buy_date: entry.date, qty: trade.qty.to_d, cost_per_unit: price)
        elsif trade.qty.negative?
          redeem(queues[key], entry, trade, account, price)
        end
      end

      @open_lots = queues.values.flatten.select { |lot| lot.qty.positive? }
    end

    def redeem(queue, entry, trade, account, price)
      remaining = trade.qty.to_d.abs
      consumed = []

      while remaining.positive? && queue.any?
        lot = queue.first

        if lot.qty <= remaining
          units = lot.qty
          queue.shift
        else
          units = remaining
          queue[0] = lot.split(units).last
        end

        remaining -= units
        consumed << RealizedLot.new(
          account: account, security: trade.security, folio: trade.folio_number, entry: entry,
          buy_date: lot.buy_date, sell_date: entry.date, qty: units,
          cost: units * lot.cost_per_unit, proceeds: units * price
        )
      end

      @unmatched_sales << { entry: entry, qty: remaining } if remaining.positive?
      return if consumed.empty?

      @realized_lots.concat(consumed)
      @redemptions << Redemption.new(account: account, security: trade.security, folio: trade.folio_number,
                                     entry: entry, date: entry.date, lots: consumed)
    end

    def unit_price(trade, date, account)
      to = target_currency || account.currency
      Money.new(trade.price, trade.currency).exchange_to(to, date: date, fallback_rate: 1).amount.to_d
    end
end
