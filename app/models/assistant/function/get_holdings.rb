class Assistant::Function::GetHoldings < Assistant::Function
  class << self
    def name
      "get_holdings"
    end

    def description
      <<~INSTRUCTIONS
        Use this to see what the user holds in their investment accounts (stocks, ETFs and mutual funds),
        with the invested amount, current value, gain, absolute return, XIRR (annualized return), 1-day
        change and CAGR since first purchase (blank until a year has passed) for each holding, trailing
        1/3/5-year CAGR for mutual funds, and the same totals for the whole portfolio. prices_as_of says when
        prices were last refreshed.

        This is great for answering questions like:
        - What is my portfolio worth, and what is my XIRR?
        - Which of my funds has returned the most?
        - What do I hold in each account?
      INSTRUCTIONS
    end
  end

  def call(params = {})
    accounts = family.accounts_with_investments.includes(:entries, :household_member).to_a
    summary = family.investment_summary(accounts: accounts)

    {
      as_of_date: Date.current,
      currency: family.currency,
      portfolio: {
        invested: summary.invested.format,
        current_value: summary.current_value.format,
        gain: summary.gain.format,
        gain_percent: percent(summary.gain_percent),
        xirr_percent: percent(summary.xirr),
        one_day_change: summary.one_day_change&.format,
        one_day_change_percent: percent(summary.one_day_change_percent),
        prices_as_of: MarketData.format_prices_as_of(summary.prices_as_of)
      },
      accounts: accounts.map { |account| account_data(account) }
    }
  end

  private
    def account_data(account)
      {
        name: account.name,
        owner: account.owner_name,
        currency: account.currency,
        # Holdings share the account, so its trades are replayed once, not once per holding
        holdings: account.current_holdings_with_returns.map { |holding| holding_data(holding) }
      }
    end

    def holding_data(holding)
      security = holding.security
      returns = holding.returns

      {
        name: security.display_name,
        ticker: security.ticker,
        kind: security.kind,
        quantity: holding.qty,
        price: Money.new(holding.price, holding.currency).format,
        current_value: holding.amount_money.format,
        invested: returns.invested.format,
        gain: returns.gain.format,
        absolute_return_percent: percent(returns.absolute_return),
        xirr_percent: percent(returns.xirr),
        one_day_change: returns.one_day_change&.format,
        one_day_change_percent: percent(returns.one_day_change_percent),
        cagr_since_first_purchase_percent: percent(returns.cagr_since_first_purchase),
        trailing_cagr_percent: trailing_cagr(security)
      }
    end

    # Mutual funds only: { "1y" => 12.0, "3y" => nil, "5y" => nil }
    def trailing_cagr(security)
      return nil unless security.amfi?

      security.trailing_returns.to_h.to_h { |years, cagr| [ "#{years}y", percent(cagr) ] }
    end

    # Fractions (0.12) become "12.0"; nil stays nil so the assistant says the figure is unavailable
    def percent(fraction)
      fraction && (fraction * 100).round(1)
    end
end
