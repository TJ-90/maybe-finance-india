class Assistant::Function::GetHoldings < Assistant::Function
  class << self
    def name
      "get_holdings"
    end

    def description
      <<~INSTRUCTIONS
        Use this to see what the user holds in their investment accounts (stocks, ETFs and mutual funds),
        with the invested amount, current value, gain and XIRR (annualized return) for each holding and for
        the whole portfolio.

        This is great for answering questions like:
        - What is my portfolio worth, and what is my XIRR?
        - Which of my funds has returned the most?
        - What do I hold in each account?
      INSTRUCTIONS
    end
  end

  def call(params = {})
    accounts = family.accounts_with_investments.includes(:entries).to_a
    summary = family.investment_summary(accounts: accounts)

    {
      as_of_date: Date.current,
      currency: family.currency,
      portfolio: {
        invested: summary.invested.format,
        current_value: summary.current_value.format,
        gain: summary.gain.format,
        gain_percent: percent(summary.gain_percent),
        xirr_percent: percent(summary.xirr)
      },
      accounts: accounts.map { |account| account_data(account) }
    }
  end

  private
    def account_data(account)
      # Replay the account's trades once, not once per holding
      cost_by_security = Holding::TaxLots.new([ account ], currency: account.currency).open_lots
                                         .group_by { |lot| lot.security.id }
                                         .transform_values { |lots| lots.sum(&:cost) }

      {
        name: account.name,
        currency: account.currency,
        holdings: account.current_holdings.includes(:security).map { |holding| holding_data(holding, cost_by_security.fetch(holding.security_id, 0)) }
      }
    end

    def holding_data(holding, invested)
      security = holding.security
      value = holding.amount

      {
        name: security.display_name,
        ticker: security.ticker,
        kind: security.kind,
        quantity: holding.qty,
        price: Money.new(holding.price, holding.currency).format,
        current_value: holding.amount_money.format,
        invested: Money.new(invested, holding.currency).format,
        gain: Money.new(value - invested, holding.currency).format,
        xirr_percent: percent(holding.xirr)
      }
    end

    # Fractions (0.12) become "12.0"; nil stays nil so the assistant says the figure is unavailable
    def percent(fraction)
      fraction && (fraction * 100).round(1)
    end
end
