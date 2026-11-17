module HouseholdHelper
  # id => name for the signed-in family's members, loaded once per request (the sidebar lists every account)
  def household_member_names
    @household_member_names ||= Current.family.household_members.pluck(:id, :name).to_h
  end

  # The owner's name, or nil when the account is joint or the family has no members yet
  def account_owner_name(account)
    household_member_names[account.household_member_id]
  end

  # "Savings · Asha": the subtype with the owner appended when there is one
  def account_subtitle(account, subtype_label)
    [ subtype_label.presence, account_owner_name(account) ].compact.join(" · ")
  end
end
