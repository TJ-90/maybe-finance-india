# Finds the AMFI scheme a fund display name refers to, for files that carry no ISIN or scheme code
# (for example a Groww order history: "Sample Bluechip Index Fund Direct Growth").
#
# Names are normalised (case, punctuation, filler words such as plan / option / fund / scheme), the plan
# (direct or regular) and option (growth or IDCW) are read from the text, and the remaining words are
# scored against each candidate scheme. Only one clear winner counts: a candidate whose plan or option
# contradicts what the text states is out, the best score must reach THRESHOLD, and it must beat the
# runner-up by at least MARGIN. Anything else returns nil, so a fund is never guessed.
#
# The plan and option of a scheme come from its structured columns (AMFI publishes them separately).
class MutualFundScheme::NameMatcher
  THRESHOLD = 0.75
  MARGIN = 0.1

  FILLER_WORDS = %w[plan option fund funds scheme the of and a an mutual].to_set.freeze
  PLAN_WORDS = { "direct" => "direct", "regular" => "regular" }.freeze
  OPTION_WORDS = {
    "growth" => "growth",
    "idcw" => "idcw", "dividend" => "idcw", "payout" => "idcw", "reinvestment" => "idcw", "reinvest" => "idcw", "bonus" => "idcw"
  }.freeze
  # Words that only describe the plan or the dividend frequency, never the fund itself
  ATTRIBUTE_WORDS = (PLAN_WORDS.keys + OPTION_WORDS.keys + %w[monthly quarterly weekly daily annual half yearly fortnightly re investment]).to_set.freeze
  SUFFIX_SEGMENT = /\b(direct|regular|plan|growth|option|idcw|dividend|payout|re-?invest\w*|bonus)\b/i

  Parsed = Data.define(:tokens, :plan, :option)
  Candidate = Data.define(:scheme, :score, :compatible)

  def initialize(scope = MutualFundScheme.active)
    @scope = scope
    @pool = {}
    @parsed = {}
  end

  # The one scheme the name stands for, or nil when there is none or more than one
  def match(name)
    best, runner_up = candidates(name, limit: 2)

    return nil if best.nil? || !best.compatible || best.score < THRESHOLD
    return nil if runner_up&.compatible && best.score - runner_up.score < MARGIN

    best.scheme
  end

  # Best candidates first (those agreeing on plan and option, then by score), for a picker
  def candidates(name, limit: 10)
    source = parse(name)
    return [] if source.tokens.empty?

    pool_for(source.tokens.first).filter_map do |scheme|
      target = parse_scheme(scheme)
      score = score(source.tokens, target.tokens)
      next if score.zero?

      Candidate.new(scheme: scheme, score: score.round(4), compatible: compatible?(source, target))
    end.sort_by { |candidate| [ candidate.compatible ? 0 : 1, -candidate.score, candidate.scheme.name ] }.first(limit)
  end

  def parse(name)
    words = normalize(name).split
    plan = words.filter_map { |word| PLAN_WORDS[word] }.first
    option = words.filter_map { |word| OPTION_WORDS[word] }.first
    Parsed.new(tokens: significant(words), plan: plan, option: option)
  end

  private
    # Schemes sharing the first significant word (the fund house brand, such as "uti" or "hdfc")
    def pool_for(brand)
      @pool[brand] ||= @scope.where("mutual_fund_schemes.name ILIKE :p OR mutual_fund_schemes.amc ILIKE :p", p: "%#{MutualFundScheme.sanitize_sql_like(brand)}%")
                             .select(:id, :scheme_code, :name, :amc, :plan, :option).to_a
    end

    def parse_scheme(scheme)
      @parsed[scheme.id] ||= begin
        base = scheme.name.to_s
        loop do
          head, separator, tail = base.rpartition(/\s+-\s+/)
          break if separator.empty? || !tail.match?(SUFFIX_SEGMENT)

          base = head
        end

        Parsed.new(tokens: significant(normalize(base).split), plan: scheme.plan, option: scheme.option)
      end
    end

    def compatible?(source, target)
      (source.plan.nil? || target.plan.nil? || source.plan == target.plan) &&
        (source.option.nil? || target.option.nil? || source.option == target.option)
    end

    # Share of all distinct words that both names have (1.0 = same words)
    def score(source_tokens, target_tokens)
      a = source_tokens.to_set
      b = target_tokens.to_set
      return 0.0 if a.empty? || b.empty?

      (a & b).size.to_f / (a | b).size
    end

    def significant(words)
      words.reject { |word| FILLER_WORDS.include?(word) || ATTRIBUTE_WORDS.include?(word) }
    end

    # Lower case words without punctuation; "mid cap" and "midcap" read alike
    def normalize(name)
      text = name.to_s.unicode_normalize(:nfkc).downcase.tr("’‘", "'").delete("'")
      text = text.gsub("&", " and ").gsub(/[^a-z0-9]+/, " ").strip
      text.gsub(/\b(mid|small|large|multi|flexi|focused|blue)\s+(cap|chip)\b/, '\1\2')
    end
end
