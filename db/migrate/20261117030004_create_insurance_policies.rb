class CreateInsurancePolicies < ActiveRecord::Migration[7.2]
  def change
    create_table :insurance_policies, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true
      t.string :kind, null: false, default: "term"
      t.string :insurer, null: false
      t.text :policy_number # encrypted by ActiveRecord encryption
      t.string :insured_names
      t.string :currency, null: false
      t.decimal :sum_assured, precision: 19, scale: 4
      t.decimal :premium, precision: 19, scale: 4
      t.string :premium_frequency, default: "yearly"
      t.date :next_premium_due_on
      t.date :start_date
      t.date :end_date
      t.string :nominee
      t.text :notes

      t.timestamps
    end

    add_index :insurance_policies, [ :family_id, :next_premium_due_on ]
  end
end
