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
end
