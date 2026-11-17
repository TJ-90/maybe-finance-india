# What changes in the Tax Center depending on whether the selected person is a resident or an NRI.
#
# Capital-gains rates and the Sec 112A exemption are the same for both. What differs is shown here:
# an NRI has TDS deducted from every sale (an estimate: cess is added, surcharge and DTAA are not
# modelled), while a resident gets notes about the basic-exemption set-off and the 87A rebate.
# All numbers come from the `residency:` section of config/india_capital_gains.yml.
class TaxCenter::Residency
  # Which TDS rate (see TaxCenter::Rules#nri_tds_rates) applies to a classified gain
  BUCKET_TDS_KEYS = {
    stcg_equity: :equity_stcg,
    ltcg_equity: :equity_ltcg,
    ltcg_other: :other_ltcg
  }.freeze

  attr_reader :member, :rules

  def initialize(member: nil, rules: TaxCenter::Rules.current)
    @member = member
    @rules = rules
  end

  # False for families that have not set up their household yet: nothing residency-specific is shown
  def known?
    member.present?
  end

  def nri?
    member&.nri? == true
  end

  def resident?
    member&.resident? == true
  end

  def label
    member&.residency_label
  end

  # Notes for the selected status: the NRI TDS notes, or the resident set-off and rebate notes
  def notes
    return [] unless known?

    rules.residency_notes(member.residency_status)
  end

  def cess_percent
    rules.nri_tds_cess_percent
  end

  def surcharge_note
    rules.nri_tds_surcharge_note
  end

  def dtaa_note
    rules.nri_tds_dtaa_note
  end

  # TDS rate in % (before cess) on one classified gain, or 0 for residents and exempt gains
  def tds_rate(classification, sell_date)
    return BigDecimal("0") unless nri?

    key = tds_key(classification)
    key ? rules.nri_tds_rates(sell_date).fetch(key) : BigDecimal("0")
  end

  # Estimated TDS on a set of gain lines (TaxCenter::GainLine) sold on one date. Gains of the same kind
  # are netted first, because TDS is deducted on the gain of the sale, never on a loss.
  def tds_for_lines(lines, sell_date)
    return BigDecimal("0") unless nri?

    lines.group_by { |line| tds_key(line.classification) }.sum(BigDecimal("0")) do |key, group|
      next BigDecimal("0") if key.nil?

      tds_for_gain(key, group.sum(&:gain), sell_date)
    end
  end

  # TDS in the family currency on `gain` taxed under `key` (one of the keys of Rules#nri_tds_rates), cess included
  def tds_for_gain(key, gain, sell_date)
    return BigDecimal("0") unless nri? && gain.to_d.positive?

    rate = rules.nri_tds_rates(sell_date).fetch(key)
    (gain.to_d * rate / 100 * (1 + cess_percent / 100)).round(2)
  end

  # The TDS rates in force on `date` in words, read from the config ("equity short term 20%, ...")
  def tds_rate_summary(date = Date.current)
    rates = rules.nri_tds_rates(date)
    labels = {
      equity_stcg: "equity short term", equity_ltcg: "equity long term", debt_mf: "specified debt funds",
      other_stcg: "other short term", other_ltcg: "other long term"
    }

    labels.map { |key, label| "#{label} #{rates.fetch(key).to_s('F').delete_suffix('.0')}%" }.to_sentence
  end

  private
    def tds_key(classification)
      return nil if classification.exempt?
      return (classification.category == "debt" ? :debt_mf : :other_stcg) if classification.slab?

      BUCKET_TDS_KEYS.fetch(classification.bucket)
    end
end
