class CreateMutualFundSchemes < ActiveRecord::Migration[7.2]
  def change
    create_table :mutual_fund_schemes, id: :uuid do |t|
      t.string :scheme_code, null: false
      t.string :name, null: false
      t.string :amc
      t.string :category
      t.string :scheme_type
      t.string :plan
      t.string :option
      t.string :isin_growth
      t.string :isin_reinvestment
      t.decimal :latest_nav, precision: 19, scale: 4
      t.date :nav_date
      t.string :asset_class
      t.string :tax_category
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :mutual_fund_schemes, :scheme_code, unique: true
    add_index :mutual_fund_schemes, :amc
    add_index :mutual_fund_schemes, :category
    add_index :mutual_fund_schemes, :isin_growth
  end
end
