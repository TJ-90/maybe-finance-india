class TransactionImport < Import
  # Statement files can have account details above the header row
  def prepare_raw_csv(csv_str, col_sep: ",")
    Import.strip_preamble(csv_str, col_sep: col_sep)
  end

  def import!
    transaction do
      mappings.each(&:create_mappable!)

      hinted_categories = []

      transactions = rows.map do |row|
        mapped_account = if account
          account
        else
          mappings.accounts.mappable_for(row.account)
        end

        category = mappings.categories.mappable_for(row.category)
        tags = row.tags_list.map { |tag| mappings.tags.mappable_for(tag) }.compact

        parsed = Transaction::NarrationParser.parse(row.name)
        hint = Transaction::MerchantHint.match(
          counterparty: parsed[:counterparty],
          vpa: parsed[:vpa],
          clean_name: parsed[:clean_name]
        )
        name = parsed[:clean_name].presence || row.name

        transaction = Transaction.new(
          category: category,
          tags: tags,
          merchant: merchant_for(hint&.merchant_name || parsed[:counterparty]),
          payment_mode: parsed[:payment_mode],
          reference_number: parsed[:reference_number],
          entry: Entry.new(
            account: mapped_account,
            date: row.date_iso,
            amount: row.signed_amount,
            name: name,
            currency: row.currency,
            notes: notes_for(row, name),
            import: self
          )
        )

        hinted_categories << [ transaction, hint.category_name ] if category.nil? && hint&.category_name.present?
        transaction
      end

      Transaction.import!(transactions, recursive: true)

      apply_category_hints(hinted_categories)
    end
  end

  def required_column_keys
    %i[date amount]
  end

  def column_keys
    base = %i[date amount name currency category tags notes]
    base.unshift(:account) if account.nil?
    base
  end

  def mapping_steps
    base = [ Import::CategoryMapping, Import::TagMapping ]
    base << Import::AccountMapping if account.nil?
    base
  end

  def selectable_amount_type_values
    return [] if entity_type_col_label.nil?

    csv_rows.map { |row| row[entity_type_col_label] }.uniq
  end

  def csv_template
    template = <<-CSV
      date*,amount*,name,currency,category,tags,account,notes
      05/15/2024,-45.99,Grocery Store,USD,Food,groceries|essentials,Checking Account,Monthly grocery run
      05/16/2024,1500.00,Salary,,Income,,Main Account,
      05/17/2024,-12.50,Coffee Shop,,,coffee,,
    CSV

    csv = CSV.parse(template, headers: true)
    csv.delete("account") if account.present?
    csv
  end

  private
    # Keeps the bank's original narration when we replaced the name with a cleaned one
    def notes_for(row, name)
      return row.notes.presence if name == row.name

      [ row.notes.presence, "Bank narration: #{row.name}" ].compact.join("\n")
    end

    def merchant_for(merchant_name)
      return if merchant_name.blank?

      @merchants ||= {}
      @merchants[merchant_name.downcase] ||= family.merchants.where("LOWER(name) = ?", merchant_name.downcase).first ||
        family.merchants.create!(name: merchant_name)
    end

    # Suggested categories are enrichments: they apply only to uncategorised, unlocked
    # transactions, are logged as such, and never replace a user, rule or AI choice.
    def apply_category_hints(hinted_categories)
      return if hinted_categories.empty?

      categories = family.categories.where(name: hinted_categories.map(&:last).uniq).index_by(&:name)

      hinted_categories.each do |transaction, category_name|
        category = categories[category_name]
        next if category.nil? || transaction.category_id.present?

        transaction.enrich_attribute(:category_id, category.id, source: :import_hint)
      end
    end
end
