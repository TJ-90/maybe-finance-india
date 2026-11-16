class TaxCenterController < ApplicationController
  DEFAULT_SLAB_RATE = BigDecimal("30")

  before_action :set_context

  helper_method :shared_params

  def show
    @breadcrumbs = [ [ "Home", root_path ], [ "Tax Center", nil ] ]
  end

  def realized_gains
  end

  def harvesting
    @harvester = build_harvester
  end

  def calculator
    @calculation = TaxCenter::Calculation.new(report: @current_year_report, inputs: calculator_params)
  end

  def categories
    @mapping = TaxCenter::CategoryMapping.new(Current.family)
  end

  def update_category
    override = TaxCenter::CategoryMapping.new(Current.family).update(
      security_id: params[:security_id],
      tax_category: params[:tax_category],
      asset_class: params[:asset_class]
    )

    if override.errors.any?
      redirect_to categories_tax_center_path(shared_params), alert: override.errors.full_messages.to_sentence
    else
      redirect_to categories_tax_center_path(shared_params), notice: "Category updated"
    end
  end

  def export
    case params[:kind]
    when "harvesting"
      send_data TaxCenter::Export.new(report: @current_year_report, harvester: build_harvester).harvesting_csv,
                filename: "harvesting-#{Date.current.iso8601}.csv", type: "text/csv"
    else
      send_data TaxCenter::Export.new(report: @report).realized_gains_csv,
                filename: "realized-gains-#{@report.label}.csv", type: "text/csv"
    end
  end

  private
    def set_context
      @available_accounts = Current.family.accounts_with_investments.to_a
      @selected_accounts = selected_accounts
      @fy_start = financial_year_start
      @slab_rate = slab_rate
      @report = build_report(@fy_start)
      @current_year_report = build_report(Period.financial_year_start(Date.current))
      @fy_options = financial_year_options
    end

    def build_report(fy_start)
      TaxCenter::Report.new(family: Current.family, accounts: @selected_accounts, financial_year_start: fy_start, slab_rate: @slab_rate)
    end

    def build_harvester
      TaxCenter::Harvester.new(family: Current.family, report: @current_year_report)
    end

    # No selection means every investment account in the family
    def selected_accounts
      ids = Array(params[:account_ids]).reject(&:blank?)
      ids.any? ? @available_accounts.select { |account| ids.include?(account.id.to_s) } : @available_accounts
    end

    def financial_year_start
      current = Period.financial_year_start(Date.current)
      year = params[:fy].to_i
      return current unless year.between?(2000, current.year)

      Period.financial_year_range(year).first
    end

    def slab_rate
      value = params[:slab].presence
      return DEFAULT_SLAB_RATE if value.nil?

      BigDecimal(value.to_s).clamp(BigDecimal("0"), BigDecimal("100"))
    rescue ArgumentError
      DEFAULT_SLAB_RATE
    end

    def financial_year_options
      current = Period.financial_year_start(Date.current).year
      first = Current.family.entries.where(entryable_type: "Trade").minimum(:date)
      first_year = first ? Period.financial_year_start(first).year : current

      (first_year..current).to_a.reverse.map { |year| [ Period.financial_year_label(Period.financial_year_range(year).first), year ] }
    end

    def calculator_params
      params.permit(:holding, :units, :sale_date, :price, :only_held_over_months, :realized_stcg, :realized_ltcg)
    end

    # Filters that every section shares, passed along in links and forms
    def shared_params
      { fy: @fy_start.year, slab: @slab_rate.to_s("F").delete_suffix(".0"), account_ids: @selected_accounts.map(&:id) }
    end
end
