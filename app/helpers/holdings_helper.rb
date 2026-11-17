module HoldingsHelper
  # One grid template for the holdings header, the cash row and every holding row, so the columns line up.
  # The name column is wide enough to read a fund name on two lines; the numeric columns never go below
  # a readable width. Below the container width the table scrolls sideways instead of squeezing the name.
  HOLDINGS_GRID_CLASSES = "grid grid-cols-[minmax(13rem,3fr)_repeat(5,minmax(6.5rem,1fr))] gap-x-4 items-center min-w-[52rem]".freeze

  def holdings_grid_classes(extra = nil)
    [ HOLDINGS_GRID_CLASSES, extra ].compact.join(" ")
  end

  # "4903.9 units" or "12 shares". Fund units go to three decimals, share counts to one.
  def format_holding_qty(holding)
    security = holding.security
    precision = security.units? ? 3 : 1
    "#{number_with_precision(holding.qty, precision: precision, strip_insignificant_zeros: security.units?)} #{security.unit_noun}"
  end
end
