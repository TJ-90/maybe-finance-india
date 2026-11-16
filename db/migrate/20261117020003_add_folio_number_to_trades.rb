class AddFolioNumberToTrades < ActiveRecord::Migration[7.2]
  def change
    add_column :trades, :folio_number, :string
    add_index :trades, [ :security_id, :folio_number ]
  end
end
