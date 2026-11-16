class CreatePreciousMetals < ActiveRecord::Migration[7.2]
  def change
    create_table :precious_metals, id: :uuid do |t|
      t.decimal :weight_grams, precision: 12, scale: 3
      t.string :purity
      t.string :form
      t.jsonb :locked_attributes, default: {}

      t.timestamps
    end
  end
end
