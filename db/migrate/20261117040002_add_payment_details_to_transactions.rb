class AddPaymentDetailsToTransactions < ActiveRecord::Migration[7.2]
  def change
    add_column :transactions, :payment_mode, :string
    add_column :transactions, :reference_number, :string
    add_index :transactions, :payment_mode
  end
end
