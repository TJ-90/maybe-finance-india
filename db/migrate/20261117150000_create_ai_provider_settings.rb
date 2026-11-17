class CreateAiProviderSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_provider_settings, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.string :provider, null: false, default: "openai"
      t.text :api_key
      t.string :base_url
      t.string :chat_model
      t.string :fast_model
      t.boolean :openrouter_attribution, null: false, default: true
      t.boolean :enabled, null: false, default: true
      t.string :last_test_status
      t.string :last_test_message
      t.datetime :last_tested_at

      t.timestamps
    end
  end
end
