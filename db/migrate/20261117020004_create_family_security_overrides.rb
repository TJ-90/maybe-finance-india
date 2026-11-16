class CreateFamilySecurityOverrides < ActiveRecord::Migration[7.2]
  def change
    create_table :family_security_overrides, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :security, null: false, foreign_key: true, type: :uuid
      t.string :tax_category
      t.string :asset_class

      t.timestamps
    end

    add_index :family_security_overrides, [ :family_id, :security_id ], unique: true
  end
end
