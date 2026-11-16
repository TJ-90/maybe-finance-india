class Import::MappingsController < ApplicationController
  before_action :set_import

  def update
    mapping = @import.mappings.find(params[:id])

    mapping.assign_attributes \
      create_when_empty: create_when_empty,
      mappable: mappable(mapping),
      value: mapping_params[:value]
    # Like sync_mappings: keep an incomplete choice; the import cannot be published until it is valid
    mapping.save!(validate: false)

    redirect_back_or_to import_confirm_path(@import)
  end

  private
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
