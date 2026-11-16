class AddExternalIdToTrades < ActiveRecord::Migration[7.2]
  def change
    # The broker's own id for a fill (e.g. Zerodha trade_id). Used to skip trades that were imported before.
    add_column :trades, :external_id, :string
    add_index :trades, :external_id
  end
end
