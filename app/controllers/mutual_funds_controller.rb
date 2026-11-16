class MutualFundsController < ApplicationController
  NAV_RANGES = {
    "1y" => 1.year,
    "3y" => 3.years,
    "5y" => 5.years,
    "max" => 25.years
  }.freeze

  PER_PAGE_OPTIONS = [ 10, 20, 30, 50 ].freeze

  def index
    @q = filter_params
    @amcs = MutualFundScheme.amcs
    @categories = MutualFundScheme.categories
    @last_nav_date = MutualFundScheme.last_nav_date

    scope = MutualFundScheme.discover(**@q.symbolize_keys).alphabetically
    @pagy, @schemes = pagy(scope, limit: per_page)
  end

  def show
    @scheme = MutualFundScheme.find(params[:id])
    @range = NAV_RANGES.key?(params[:range]) ? params[:range] : "1y"

    history = @scheme.nav_history(since: NAV_RANGES.fetch(@range).ago.to_date)
    @nav_series = build_series(history)
    @investment_accounts = Current.family.accounts.visible.where(accountable_type: "Investment").alphabetically
  end

  private
    def filter_params
      params.fetch(:q, {}).permit(:q, :amc, :category, :plan, :option, :style).to_h
    end

    def per_page
      requested = params[:per_page].to_i
      PER_PAGE_OPTIONS.include?(requested) ? requested : 20
    end

    def build_series(history)
      return nil if history.size < 2

      Series.from_raw_values(
        history.map { |date, nav| { date: date, value: Money.new(nav, "INR") } }
      )
    end
end
