class AddDebitCreditColumnsToImports < ActiveRecord::Migration[7.2]
  def change
    add_column :imports, :debit_col_label, :string
    add_column :imports, :credit_col_label, :string
  end
end
