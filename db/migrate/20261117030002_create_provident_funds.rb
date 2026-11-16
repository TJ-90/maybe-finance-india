class CreateProvidentFunds < ActiveRecord::Migration[7.2]
  def change
    create_table :provident_funds, id: :uuid do |t|
      # Null means "use the default for the subtype from config/india_small_savings_rates.yml"
      t.decimal :interest_rate, precision: 7, scale: 3
      t.decimal :monthly_contribution, precision: 19, scale: 4
      t.decimal :employer_contribution, precision: 19, scale: 4
      t.date :opened_on
      t.date :maturity_date
      t.string :account_number_last4
      t.jsonb :locked_attributes, default: {}

      t.timestamps
    end
  end
end
