class CreateNotificationPreferences < ActiveRecord::Migration[7.2]
  def change
    create_table :notification_preferences, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.boolean :email_enabled, null: false, default: false
      t.boolean :include_amounts, null: false, default: false
      t.boolean :monthly_summary, null: false, default: true
      t.integer :stale_data_days, null: false, default: 35
      t.string :disabled_kinds, array: true, null: false, default: []

      t.timestamps
    end
  end
end
