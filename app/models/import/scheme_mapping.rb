# Maps a fund name from the file (a Groww order history has no ISIN or scheme code) to an AMFI
# MutualFundScheme. Names that MutualFundScheme::NameMatcher resolves unambiguously are pre-selected;
# the rest must be chosen by the user before the import can be published.
class Import::SchemeMapping < Import::Mapping
  validates :mappable, presence: true

  CANDIDATE_LIMIT = 15
  SEARCH_LIMIT = 50

  class << self
    def mappables_by_key(import)
      matcher = MutualFundScheme::NameMatcher.new
      chosen = import.mappings.where(type: name).includes(:mappable).index_by(&:key)

      import.fund_names_to_resolve.index_with do |fund_name|
        chosen[fund_name]&.mappable || matcher.match(fund_name)
      end
    end
  end

  # Schemes to pick from: a search (name, AMC, scheme code or ISIN) when the user typed one, otherwise
  # the best name matches for the fund in the file. The current choice is always included.
  def selectable_values(search = nil)
    schemes = if search.present?
      MutualFundScheme.active.search(search).alphabetically.limit(SEARCH_LIMIT).to_a
    else
      MutualFundScheme::NameMatcher.new.candidates(key, limit: CANDIDATE_LIMIT).map(&:scheme)
    end

    schemes.unshift(mappable) if mappable && schemes.none? { |scheme| scheme.id == mappable.id }
    schemes.map { |scheme| [ "#{scheme.name} (#{scheme.scheme_code})", scheme.id ] }
  end

  def requires_selection?
    true
  end

  def values_count
    import.rows.where(ticker: key).count
  end

  def mappable_class
    MutualFundScheme
  end

  # Schemes belong to no family
  def find_mappable(id, _family)
    MutualFundScheme.find_by(id: id)
  end

  def create_mappable!
    # no-op: a scheme has to be chosen
  end
end
