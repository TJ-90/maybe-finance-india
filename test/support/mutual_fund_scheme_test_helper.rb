# Schemes named the way AMFI publishes them (plan and option are also separate columns). They are created
# per test rather than as fixtures so that tests counting the fixture schemes are not affected.
module MutualFundSchemeTestHelper
  SIGMA_SCHEMES = {
    nifty_direct: [ "400001", "Sigma Alpha Index Fund - Direct Plan - Growth Option", "direct", "growth", "INF000S01001" ],
    nifty_regular: [ "400002", "Sigma Alpha Index Fund - Regular Plan - Growth Option", "regular", "growth", "INF000S01002" ],
    nifty_idcw_direct: [ "400003", "Sigma Alpha Index Fund - Direct Plan - IDCW Option", "direct", "idcw", nil ],
    next_nifty_direct: [ "400004", "Sigma Alpha Next Index Fund - Direct Plan - Growth Option", "direct", "growth", "INF000S01004" ],
    midcap_direct: [ "400005", "Sigma Midcap Fund - Direct Plan - Growth Option", "direct", "growth", "INF000S01005" ]
  }.freeze

  def create_sigma_schemes
    SIGMA_SCHEMES.transform_values do |code, name, plan, option, isin|
      MutualFundScheme.create!(
        scheme_code: code, name: name, amc: "Sigma Sample Mutual Fund", category: "Other Scheme - Index Funds",
        scheme_type: "Open Ended", plan: plan, option: option, isin_growth: isin, latest_nav: 100,
        nav_date: Date.new(2026, 11, 1), asset_class: "equity", tax_category: "equity", active: true
      )
    end
  end
end
