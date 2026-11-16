class CreateFixedDeposits < ActiveRecord::Migration[7.2]
  def change
    create_table :fixed_deposits, id: :uuid do |t|
      t.decimal :interest_rate, precision: 7, scale: 3
      t.string :compounding, default: "quarterly"
      t.string :payout, default: "cumulative"
      t.date :start_date
      t.date :maturity_date
      t.decimal :principal, precision: 19, scale: 4
      t.decimal :monthly_installment, precision: 19, scale: 4
      t.string :institution_name
      t.boolean :auto_renew, default: false, null: false
      t.jsonb :locked_attributes, default: {}

      t.timestamps
    end
  end
end
