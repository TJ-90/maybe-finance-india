# Money-weighted returns (XIRR) from an account's trade cash flows.
module Account::Returns
  extend ActiveSupport::Concern

  # Cash flows seen from the investor: buys are outflows (negative), sells are inflows (positive).
  # Entry amounts follow Maybe's convention (positive = money leaving the account), so the sign is flipped.
  def trade_cash_flows(security: nil)
    scope = entries.where(entryable_type: "Trade").includes(:entryable)
    scope = scope.where(entryable_id: Trade.where(security_id: security.id).select(:id)) if security

    scope.map do |entry|
      amount = Money.new(entry.amount, entry.currency).exchange_to(currency, date: entry.date, fallback_rate: 1).amount
      [ entry.date, -amount ]
    end
  end

  # Latest market value of everything held in the account (or of one security)
  def securities_value(security: nil)
    holdings = current_holdings
    holdings = holdings.where(security_id: security.id) if security
    holdings.sum(:amount)
  end

  # Annualized return as a fraction (0.12 = 12%), or nil when it can't be computed.
  # The current value counts as a final inflow today.
  def xirr(security: nil, terminal_value: nil)
    flows = trade_cash_flows(security: security)
    return nil if flows.empty?

    value = terminal_value || securities_value(security: security)
    flows += [ [ Date.current, value ] ] if value.to_d.positive?

    Xirr.new(flows).rate
  end

  # The account's trades replayed FIFO, once per account instance (what is held, at what cost)
  def tax_lots
    @tax_lots ||= Holding::TaxLots.new([ self ], currency: currency)
  end

  # FIFO cost of the units still held
  def invested_money
    Money.new(tax_lots.open_lots.sum(&:cost), currency)
  end

  # Current holdings that share this account instance, so each holding's returns reuse tax_lots
  # instead of replaying the trades again
  def current_holdings_with_returns
    current_holdings.includes(:security).to_a.each { |holding| holding.association(:account).target = self }
  end

  # How much the securities moved in value since their previous price (Money), nil when no holding has one
  def one_day_change
    changes = current_holdings_with_returns.filter_map { |holding| holding.returns.one_day_change }
    return nil if changes.empty?

    Money.new(changes.sum(&:amount), currency)
  end

  # One-day change as a fraction of yesterday's value
  def one_day_change_percent
    change = one_day_change
    return nil if change.nil?

    previous = securities_value - change.amount
    previous.positive? ? change.amount / previous : nil
  end

  # When the prices behind the holdings were last written (a Time), nil without any
  def prices_last_updated_at
    Security::Price.where(security_id: current_holdings.select(:security_id)).maximum(:updated_at)
  end
end
