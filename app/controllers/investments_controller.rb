class InvestmentsController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(:id, :tracks_cash)
end
