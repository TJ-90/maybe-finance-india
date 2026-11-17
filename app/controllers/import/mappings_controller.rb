class Import::MappingsController < ApplicationController
  before_action :set_import

  def update
    mapping = @import.mappings.find(params[:id])

    mapping.assign_attributes \
      create_when_empty: create_when_empty,
      mappable: mappable(mapping)
    # Only forms that post a value change it: the account step keeps the owner chosen separately
    mapping.value = mapping_params[:value] if mapping_params.key?(:value)
    # Like sync_mappings: keep an incomplete choice; the import cannot be published until it is valid
    mapping.save!(validate: false)

    redirect_back_or_to import_confirm_path(@import)
  end

  # "Whose account is this?" for an account that will be created: an existing member, Joint, or a new person
  def owner
    mapping = @import.mappings.find(params[:id])

    if params[:new_member].present?
      member = Current.family.household_members.new(new_member_params)

      unless member.save
        return redirect_back_or_to(import_confirm_path(@import), alert: member.errors.full_messages.to_sentence)
      end

      mapping.value = member.id
    elsif params[:household_member_id] == Import::AccountMapping::JOINT_VALUE
      mapping.value = Import::AccountMapping::JOINT_VALUE
    else
      mapping.value = Current.family.household_members.find(params[:household_member_id]).id
    end

    mapping.save!(validate: false)
    redirect_back_or_to import_confirm_path(@import)
  end

  private
    def new_member_params
      params.require(:new_member).permit(:name, :relationship, :residency_status)
    end

    def mapping_params
      params.require(:import_mapping).permit(:type, :key, :mappable_id, :mappable_type, :value)
    end

    def set_import
      @import = Current.family.imports.find(params[:import_id])
    end

    def mappable(mapping)
      return nil unless mappable_class.present?

      mapping.find_mappable(mapping_params[:mappable_id], Current.family)
    end

    def create_when_empty
      return false unless mapping_class.present?

      mapping_params[:mappable_id] == mapping_class::CREATE_NEW_KEY
    end

    def mappable_class
      mapping_params[:mappable_type]&.constantize
    end

    def mapping_class
      mapping_params[:type]&.constantize
    end
end
