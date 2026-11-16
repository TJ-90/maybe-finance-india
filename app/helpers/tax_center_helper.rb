module TaxCenterHelper
  DISCLAIMER = "Indicative estimates only. Surcharge, cess and rebates are not computed. Consult a tax professional.".freeze

  BUCKET_LABELS = {
    stcg_equity: "STCG (equity)",
    ltcg_equity: "LTCG (equity)",
    slab: "Taxed at slab rate",
    ltcg_other: "LTCG (other assets)",
    exempt: "Exempt"
  }.freeze

  CATEGORY_LABELS = {
    "equity" => "Equity (listed shares, equity funds)",
    "debt" => "Specified debt fund (Sec 50AA)",
    "other_listed" => "Other listed (gold ETF, bonds)",
    "other_unlisted" => "Other unlisted (hybrid, FoF)",
    "exempt" => "Exempt (SGB at maturity)"
  }.freeze

  def tax_money(amount)
    format_money(Money.new(amount, Current.family.currency))
  end

  def tax_units(quantity)
    number_with_precision(quantity, precision: 3, strip_insignificant_zeros: true)
  end

  def tax_rate_label(classification)
    return "Exempt" if classification.exempt?
    return "Slab" if classification.rate.nil?

    "#{classification.rate.to_s('F').sub(/\.0\z/, '')}%"
  end

  def tax_term_label(term)
    term == :long ? "Long term" : "Short term"
  end

  def tax_gain_class(amount)
    amount.to_d.negative? ? "text-destructive" : "text-success"
  end

  def tax_category_options
    CATEGORY_LABELS.map { |value, label| [ label, value ] }
  end

  def tax_asset_class_options
    Security::ASSET_CLASSES.map { |value| [ value.humanize, value ] }
  end

  def tax_date(date)
    date.strftime(Current.family.date_format.presence || "%d-%m-%Y")
  end
end
