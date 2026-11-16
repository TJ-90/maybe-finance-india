# Some accountables (fixed deposits, provident funds) have entries the system derives from their
# terms rather than from the user: month-end value accruals, interest credits, interest payouts.
#
# Those entries carry `entries.generated_by` (a source key such as "fixed_deposit_value"), which makes
# them distinguishable from user-entered entries and lets us delete + recreate them on every sync.
#
# Rules that keep this idempotent and safe:
# 1. Only entries with `generated_by = source` AND `generated_user_edited = false` are ever deleted.
# 2. Once a user edits a generated entry (see Entry#mark_generated_entry_as_user_edited) it becomes
#    user-owned: it is never deleted, and we do not regenerate an entry on top of it.
# 3. A generated valuation is never written on a date that already has any other valuation (the
#    opening anchor, a manual reconciliation, ...), because valuations are unique per account and date.
module Account::GeneratedEntries
  extend ActiveSupport::Concern

  # Called from Account::Syncer before balances are materialized
  def generate_auto_entries!
    accountable.generate_auto_entries! if accountable.respond_to?(:generate_auto_entries!)
  end

  # specs: [{ date:, name:, amount:, entryable: <unsaved Valuation or Transaction> }]
  def replace_generated_entries!(source, specs)
    transaction do
      entries.auto_generated.where(generated_by: source).destroy_all

      taken_valuation_dates = entries.valuations.pluck(:date).to_set
      edited_keys = entries.where(generated_by: source, generated_user_edited: true)
                           .pluck(:date, :entryable_type).to_set

      specs.each do |spec|
        entryable = spec.fetch(:entryable)
        date = spec.fetch(:date)

        if entryable.is_a?(Valuation)
          next if taken_valuation_dates.include?(date)
          taken_valuation_dates << date
        else
          next if edited_keys.include?([ date, entryable.class.name ])
        end

        entries.create!(
          date: date,
          name: spec.fetch(:name),
          amount: spec.fetch(:amount),
          currency: currency,
          entryable: entryable,
          generated_by: source
        )
      end
    end
  end
end
