class CreateNotifications < ActiveRecord::Migration[7.2]
  def change
    create_table :notifications, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :family, type: :uuid, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :title, null: false
      t.text :body
      t.text :detail
      t.string :url
      t.string :dedupe_key
      t.datetime :read_at
      t.datetime :emailed_at

      t.timestamps
    end

    add_index :notifications, [ :user_id, :dedupe_key ], unique: true, where: "dedupe_key IS NOT NULL"
    add_index :notifications, [ :user_id, :read_at ]
  end
end
