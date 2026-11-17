class CreateHouseholdMembers < ActiveRecord::Migration[7.2]
  def change
    create_table :household_members, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :relationship, null: false
      # Deliberately no default: every member is asked "Resident or NRI?" explicitly
      t.string :residency_status, null: false
      t.date :date_of_birth
      t.string :pan_last4
      t.decimal :slab_rate, precision: 5, scale: 2
      t.string :tax_regime, null: false, default: "new"
      t.string :color

      t.timestamps
    end
  end
end
