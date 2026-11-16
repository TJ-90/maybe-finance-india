# The equity share of a goal's portfolio over time. It stays at the initial level until
# `glide_path_years` before the target date, then de-risks linearly (by day) to the final level on
# the target date.
class Goal::GlidePath
  Row = Data.define(:date, :equity_pct, :debt_pct)

  attr_reader :initial_equity_pct, :final_equity_pct, :glide_path_years, :target_date

  def initialize(initial_equity_pct:, final_equity_pct:, glide_path_years:, target_date:)
    @initial_equity_pct = initial_equity_pct.to_f
    @final_equity_pct = final_equity_pct.to_f
    @glide_path_years = glide_path_years.to_i
    @target_date = target_date
  end

  def start_date
    target_date - glide_path_years.years
  end

  def equity_pct_for(date)
    return final_equity_pct if date >= target_date
    return initial_equity_pct if date <= start_date

    total_days = (target_date - start_date).to_f
    elapsed_days = (date - start_date).to_f

    initial_equity_pct + (final_equity_pct - initial_equity_pct) * (elapsed_days / total_days)
  end

  def debt_pct_for(date)
    100.0 - equity_pct_for(date)
  end

  # One row per year from `from` until the target date, ending with the target date itself
  def table(from: Date.current)
    dates = []
    date = from
    while date < target_date
      dates << date
      date = date.next_year
    end
    dates << target_date

    dates.map do |d|
      Row.new(date: d, equity_pct: equity_pct_for(d), debt_pct: debt_pct_for(d))
    end
  end
end
