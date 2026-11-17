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

  def interest
    @interest = TaxCenter::InterestIncome.new(
      family: Current.family, accounts: interest_accounts, financial_year_start: @fy_start, residency: @residency
    )
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
      @members = Current.family.household_members.ordered.to_a
      @member = selected_member
      @residency = TaxCenter::Residency.new(member: @member)
      @available_accounts = Current.family.accounts_with_investments.to_a
      @selected_accounts = selected_accounts
      @fy_start = financial_year_start
      @slab_rate = slab_rate
      @report = build_report(@fy_start)
      @current_year_report = build_report(Period.financial_year_start(Date.current))
      @fy_options = financial_year_options
    end

    def build_report(fy_start)
      TaxCenter::Report.new(family: Current.family, accounts: @selected_accounts, financial_year_start: fy_start,
                            slab_rate: @slab_rate, residency: @residency)
    end

    def build_harvester
      TaxCenter::Harvester.new(family: Current.family, report: @current_year_report)
    end

    # The person whose tax is shown. Families without household members keep the account-based view.
    # Without a valid `member_id` it is you (relationship "self"), else the first member.
    def selected_member
      return nil if @members.empty?

      @members.find { |member| member.id == params[:member_id] } || @members.find(&:myself?) || @members.first
    end

    # Accounts typed into the "advanced" disclosure win. Otherwise it is the member's investment accounts
    # (joint accounts belong to nobody, so they are only reachable through the disclosure), or every
    # investment account when no household members exist yet.
    def selected_accounts
      ids = Array(params[:account_ids]).reject(&:blank?)

      if ids.any?
        @available_accounts.select { |account| ids.include?(account.id.to_s) }
      elsif @member
        @available_accounts.select { |account| account.household_member_id == @member.id }
      else
        @available_accounts
      end
    end

    # Interest comes from every kind of account the member holds, not only investment accounts
    def interest_accounts
      accounts = Current.family.accounts.visible.alphabetically
      accounts = accounts.where(household_member_id: @member.id) if @member
      accounts.to_a
    end

    def financial_year_start
      current = Period.financial_year_start(Date.current)
      year = params[:fy].to_i
      return current unless year.between?(2000, current.year)

      Period.financial_year_range(year).first
    end

    # The rate typed in, else the selected member's own rate (30% for an NRI unless changed)
    def slab_rate
      value = params[:slab].presence
      return default_slab_rate if value.nil?

      BigDecimal(value.to_s).clamp(BigDecimal("0"), BigDecimal("100"))
    rescue ArgumentError
      default_slab_rate
    end

    def default_slab_rate
      @member&.tax_slab_rate || DEFAULT_SLAB_RATE
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

    # Filters that every section shares, passed along in links and forms. The slab rate and chosen accounts
    # are only passed on when typed in, so switching person falls back to that person's own defaults.
    def shared_params
      {
        fy: @fy_start.year,
        member_id: @member&.id,
        slab: params[:slab].presence && @slab_rate.to_s("F").delete_suffix(".0"),
        account_ids: Array(params[:account_ids]).reject(&:blank?).presence
      }.compact
    end
end
