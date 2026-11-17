class Import::AccountMapping < Import::Mapping
  validates :mappable, presence: true, if: :requires_mapping?

  class << self
    def mappables_by_key(import)
      unique_values = import.rows.map(&:account).uniq
      scope = import.respond_to?(:investment_account_scope) ? import.investment_account_scope : import.family.accounts
      accounts = scope.where(name: unique_values).index_by(&:name)

      unique_values.index_with { |value| accounts[value] }
    end
  end

  def selectable_values
    scope = import.respond_to?(:investment_account_scope) ? import.investment_account_scope : import.family.accounts
    family_accounts = scope.manual.alphabetically.map { |account| [ account.name, account.id ] }

    unless key.blank?
      family_accounts.unshift [ "Add as new account", CREATE_NEW_KEY ]
    end

    family_accounts
  end

  def requires_selection?
    true
  end

  def values_count
    import.rows.where(account: key).count
  end

  def mappable_class
    Account
  end

  JOINT_VALUE = "joint".freeze

  # Whose account a newly created one will be. The person chosen on the mapping step (stored in `value`,
  # "joint" for nobody), else a member whose first name appears in the statement's name for the account.
  def owner
    return nil if value == JOINT_VALUE

    members = import.family.household_members
    return members.find_by(id: value) if value.present?

    members.ordered.find { |member| member.first_name.present? && key.to_s.downcase.include?(member.first_name.downcase) }
  end

  def create_mappable!
    return unless creatable?

    account = if import.respond_to?(:create_investor_account!)
      import.create_investor_account!(key, owner: owner)
    else
      import.family.accounts.create_or_find_by!(name: key) do |new_account|
        new_account.balance = 0
        new_account.import = import
        new_account.currency = import.family.currency
        new_account.accountable = Depository.new
        new_account.household_member = owner
      end
    end

    self.mappable = account
    save!
  end

  private
    def requires_mapping?
      (key.blank? || !create_when_empty) && import.account.nil?
    end
end
