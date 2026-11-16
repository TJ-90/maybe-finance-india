class CreateGoalAllocations < ActiveRecord::Migration[7.2]
  def change
    create_table :goal_allocations, id: :uuid do |t|
      t.references :goal, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :security, type: :uuid, null: true, foreign_key: true
      t.decimal :percentage, precision: 5, scale: 2, null: false

      t.timestamps
    end

    add_index :goal_allocations, [ :goal_id, :account_id, :security_id ], unique: true, name: "index_goal_allocations_on_goal_account_security"
    add_index :goal_allocations, [ :account_id, :security_id ]
  end
end
