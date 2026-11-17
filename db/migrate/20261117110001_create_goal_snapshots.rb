class CreateGoalSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :goal_snapshots, id: :uuid do |t|
      t.references :goal, type: :uuid, null: false, foreign_key: true
      t.date :date, null: false
      t.string :status, null: false
      t.decimal :progress_pct, precision: 7, scale: 2, null: false, default: 0
      t.decimal :projected_corpus, precision: 19, scale: 4, null: false, default: 0
      t.decimal :target_corpus, precision: 19, scale: 4, null: false, default: 0
      t.decimal :required_sip, precision: 19, scale: 4
      t.decimal :shortfall, precision: 19, scale: 4, null: false, default: 0

      t.timestamps
    end

    add_index :goal_snapshots, [ :goal_id, :date ], unique: true
  end
end
