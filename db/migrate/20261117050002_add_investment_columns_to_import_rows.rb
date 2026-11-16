class AddInvestmentColumnsToImportRows < ActiveRecord::Migration[7.2]
  def change
    add_column :import_rows, :isin, :string
    add_column :import_rows, :folio_number, :string
    add_column :import_rows, :external_id, :string
  end
end
