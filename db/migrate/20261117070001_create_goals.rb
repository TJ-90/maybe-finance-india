class CreateGoals < ActiveRecord::Migration[7.2]
  def change
    create_table :goals, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "custom"
      t.decimal :target_amount, precision: 19, scale: 4, null: false, default: 0
      t.string :currency, null: false
      t.date :target_date, null: false
      t.decimal :inflation_rate, precision: 5, scale: 2, null: false, default: 6.0
      t.decimal :expected_equity_return, precision: 5, scale: 2, null: false, default: 12.0
      t.decimal :expected_debt_return, precision: 5, scale: 2, null: false, default: 7.0
      t.decimal :monthly_sip, precision: 19, scale: 4, null: false, default: 0
      t.decimal :sip_step_up_pct, precision: 5, scale: 2, null: false, default: 10.0
      t.decimal :initial_equity_pct, precision: 5, scale: 2, null: false, default: 70.0
      t.decimal :final_equity_pct, precision: 5, scale: 2, null: false, default: 30.0
      t.integer :glide_path_years, null: false, default: 5
      t.text :notes

      # Retirement goals only
      t.integer :current_age
      t.integer :retirement_age
      t.integer :life_expectancy
      t.decimal :monthly_expenses_today, precision: 19, scale: 4
      t.decimal :post_retirement_return, precision: 5, scale: 2, default: 8.0

      t.timestamps
    end

    add_index :goals, [ :family_id, :target_date ]
  end
end
