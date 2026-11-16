class AddIndiaFieldsToSecurities < ActiveRecord::Migration[7.2]
  def change
    add_column :securities, :kind, :string
    add_column :securities, :isin, :string
    add_column :securities, :asset_class, :string
    add_column :securities, :tax_category, :string

    add_index :securities, :isin
  end
end
