class InsurancePoliciesController < ApplicationController
  before_action :set_insurance_policy, only: %i[edit update destroy mark_premium_paid]

  def index
    @insurance_policies = Current.family.insurance_policies.ordered

    render layout: "settings"
  end

  def new
    @insurance_policy = Current.family.insurance_policies.new(
      currency: Current.family.currency,
      kind: "term",
      premium_frequency: "yearly"
    )
  end

  def create
    @insurance_policy = Current.family.insurance_policies.new(insurance_policy_params)
    @insurance_policy.documents.attach(new_documents) if new_documents.any?

    if @insurance_policy.save
      redirect_to insurance_policies_path, notice: "Policy added"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    # New files are added to the existing ones rather than replacing them
    if @insurance_policy.update(insurance_policy_params) && attach_new_documents
      redirect_to insurance_policies_path, notice: "Policy updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @insurance_policy.destroy!
    redirect_to insurance_policies_path, notice: "Policy deleted"
  end

  def mark_premium_paid
    @insurance_policy.advance_premium_due!
    redirect_back_or_to insurance_policies_path, notice: "Premium marked as paid"
  end

  private
    def set_insurance_policy
      @insurance_policy = Current.family.insurance_policies.find(params[:id])
    end

    def insurance_policy_params
      params.require(:insurance_policy).permit(
        :kind, :insurer, :policy_number, :insured_names, :currency, :sum_assured, :premium,
        :premium_frequency, :next_premium_due_on, :start_date, :end_date, :nominee, :notes
      )
    end

    def new_documents
      Array(params.dig(:insurance_policy, :documents)).select { |file| file.respond_to?(:content_type) }
    end

    def attach_new_documents
      return true if new_documents.empty?

      @insurance_policy.documents.attach(new_documents)
      @insurance_policy.errors.empty?
    end
end
