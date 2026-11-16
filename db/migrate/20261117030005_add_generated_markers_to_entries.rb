class AddGeneratedMarkersToEntries < ActiveRecord::Migration[7.2]
  def change
    # Marks entries written by the system (FD accruals, provident fund interest) so they can be
    # deleted and recreated idempotently, and never confused with user-entered entries.
    add_column :entries, :generated_by, :string
    # Set when a user edits a generated entry. The entry is then user-owned and never regenerated.
    add_column :entries, :generated_user_edited, :boolean, default: false, null: false

    add_index :entries, [ :account_id, :generated_by ], where: "generated_by IS NOT NULL"
  end
end
