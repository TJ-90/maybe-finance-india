class AddHouseholdMemberToUsers < ActiveRecord::Migration[7.2]
  def change
    add_reference :users, :household_member, type: :uuid, null: true, foreign_key: { on_delete: :nullify }
  end
end
