class Trade < ApplicationRecord
  include Entryable, Monetizable

  monetize :price

  belongs_to :security

  validates :qty, presence: true
  validates :price, :currency, presence: true

  class << self
    # Name of an auto-named trade entry. Pass the Security so mutual funds read
    # "Buy 3.368 units of <fund name>" (their ticker is a numeric AMFI code); stocks and ETFs read
    # "Buy 10.0 shares of RELIANCE". A plain string is treated as a share ticker.
    def build_name(type, qty, security_or_ticker)
      prefix = type == "buy" ? "Buy" : "Sell"
      quantity = qty.to_d.abs

      if security_or_ticker.is_a?(Security)
        security = security_or_ticker

        if security.amfi? || security.kind_mutual_fund?
          "#{prefix} #{quantity} units of #{security.display_name}"
        else
          "#{prefix} #{quantity} shares of #{security.ticker}"
        end
      else
        "#{prefix} #{quantity} shares of #{security_or_ticker}"
      end
    end

    # One-off data fix (rake data_migration:rename_auto_named_trades): older versions named trades after the
    # ticker, which for a mutual fund is the AMFI code ("Buy 3.368 900003"). Renames only entries whose name
    # is exactly one of the old generated patterns for that very trade; anything else is a user's name.
    # Returns the number of renamed entries.
    def rename_auto_named!
      renamed = 0

      Entry.where(entryable_type: "Trade").includes(entryable: :security).find_each do |entry|
        trade = entry.entryable
        security = trade&.security
        next if security.nil?

        new_name = build_name(trade.qty.negative? ? "sell" : "buy", trade.qty, security)
        next if entry.name == new_name || !legacy_names(trade, security).include?(entry.name)

        entry.update_columns(name: new_name)
        renamed += 1
      end

      renamed
    end

    private
      # Every name an earlier version generated for this trade: "Buy 3.368 900003" (demo data),
      # "Buy 3.368 shares of 900003" (trade form) and "Buy 900003" (broker and mutual fund templates)
      def legacy_names(trade, security)
        verb = trade.qty.negative? ? "Sell" : "Buy"
        quantity = trade.qty.to_d.abs
        quantities = [ quantity.to_s, quantity.to_i == quantity ? quantity.to_i.to_s : nil ].compact
        labels = [ security.ticker, security.isin, security.name ].compact_blank.uniq

        labels.flat_map do |label|
          [ "#{verb} #{label}" ] + quantities.flat_map { |q| [ "#{verb} #{q} shares of #{label}", "#{verb} #{q} #{label}" ] }
        end
      end
  end

  def unrealized_gain_loss
    return nil if qty.negative?
    current_price = security.current_price
    return nil if current_price.nil?

    current_value = current_price * qty.abs
    cost_basis = price_money * qty.abs

    Trend.new(current: current_value, previous: cost_basis)
  end
end
