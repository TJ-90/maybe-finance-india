class FixedDepositsController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id, :interest_rate, :compounding, :payout, :start_date, :maturity_date,
    :principal, :monthly_installment, :institution_name, :auto_renew
  )

  # The account's balance comes from the deposit's terms (the form has no balance field):
  # the amount invested for an FD, the first installment for an RD.
  def create
    attrs = params.dig(:account, :accountable_attributes)

    if params[:account].present? && attrs.present? && params[:account][:balance].blank?
      params[:account][:balance] = attrs[:principal].presence || attrs[:monthly_installment].presence || 0
    end

    super
  end
end
