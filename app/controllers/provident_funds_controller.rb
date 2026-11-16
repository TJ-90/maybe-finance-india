class ProvidentFundsController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id, :interest_rate, :monthly_contribution, :employer_contribution,
    :opened_on, :maturity_date, :account_number_last4
  )
end
