class AddHouseholdMemberToAccounts < ActiveRecord::Migration[7.2]
  def change
    # nil means "Joint / household"
    add_reference :accounts, :household_member, type: :uuid, null: true, foreign_key: { on_delete: :nullify }
  end
end
