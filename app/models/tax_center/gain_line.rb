# One lot (or part of a lot) that was sold, with its tax classification.
class TaxCenter::GainLine
  attr_reader :lot, :classification

  delegate :account, :security, :folio, :buy_date, :sell_date, :qty, :cost, :proceeds, :gain, :holding_days, to: :lot
  delegate :term, :bucket, :rate, :notes, to: :classification

  def initialize(lot:, classification:)
    @lot = lot
    @classification = classification
  end

  def self.for(lot, family:, rules: TaxCenter::Rules.current, category_cache: {})
    category = category_cache.fetch(lot.security.id) { category_cache[lot.security.id] = lot.security.effective_tax_category(family) }
    new(lot: lot, classification: rules.classify(category: category, buy_date: lot.buy_date, sell_date: lot.sell_date))
  end
end
