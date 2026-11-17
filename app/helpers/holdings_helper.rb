module HoldingsHelper
  # One grid template for the holdings header, the cash row and every holding row, so the columns line up.
  # Four columns: name (takes the slack, weight and average cost sit under it), value and quantity, total
  # return, XIRR. It sizes off the container (not the viewport), so it fits the narrow main column that
  # is left when both sidebars are open. Below @md the row stacks into two lines: name and value on top,
  # return and XIRR underneath.
  HOLDINGS_GRID_CLASSES = "grid grid-cols-2 @md:grid-cols-[minmax(0,1fr)_6.5rem_5.5rem_5rem] gap-x-3 gap-y-2 items-start".freeze

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
