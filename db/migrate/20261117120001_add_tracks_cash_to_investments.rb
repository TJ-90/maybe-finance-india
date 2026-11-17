class AddTracksCashToInvestments < ActiveRecord::Migration[7.2]
  # Mutual fund, NPS and ULIP accounts have no cash: purchases are paid from a bank account
  # and the order history only records the purchase. Those accounts become holdings-only.
  HOLDINGS_ONLY_SUBTYPES = %w[mutual_fund nps_tier1 nps_tier2 ulip].freeze

  def up
    add_column :investments, :tracks_cash, :boolean, null: false, default: true

    backfill
  end

  # Public so the test can run it against fixture data
  def backfill
    execute <<~SQL.squish
      UPDATE investments SET tracks_cash = FALSE
      WHERE id IN (
        SELECT accountable_id FROM accounts
        WHERE accountable_type = 'Investment'
          AND subtype IN (#{HOLDINGS_ONLY_SUBTYPES.map { |s| "'#{s}'" }.join(", ")})
      )
    SQL
  end

  def down
    remove_column :investments, :tracks_cash
  end
end
