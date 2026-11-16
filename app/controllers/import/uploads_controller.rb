class Import::UploadsController < ApplicationController
  layout "imports"

  before_action :set_import

  def show
  end

  def sample_csv
    send_data @import.csv_template.to_csv,
      filename: "#{@import.type.underscore.split('_').first}_sample.csv",
      type: "text/csv",
      disposition: "attachment"
  end

  def update
    return update_from_pdf if @import.is_a?(CasImport)

    if csv_valid?(csv_str)
      @import.account = Current.family.accounts.find_by(id: params.dig(:import, :account_id))
      @import.assign_attributes(raw_file_str: csv_str, col_sep: upload_params[:col_sep])
      @import.save!(validate: false)

      redirect_to import_configuration_path(@import, template_hint: true), notice: "CSV uploaded successfully."
    else
      flash.now[:alert] = "Must be valid CSV with headers and at least one row of data"

      render :show, status: :unprocessable_entity
    end
  end

  private
    # The statement PDF and its password are read right here and then dropped: they are never saved
    # and never handed to a background job.
    def update_from_pdf
      @import.load_pdf!(params.dig(:import, :pdf_file), password: params.dig(:import, :pdf_password))

      redirect_to import_clean_path(@import), notice: "Statement read successfully."
    rescue CasImport::Error => error
      flash.now[:alert] = error.message
      render :show, status: :unprocessable_entity
    end

    def set_import
      @import = Current.family.imports.find(params[:import_id])
    end

    def csv_str
      @csv_str ||= begin
        raw = upload_params[:csv_file]&.read || upload_params[:raw_file_str]
        raw.nil? ? raw : @import.prepare_raw_csv(raw, col_sep: upload_params[:col_sep].presence || ",")
      end
    end

    def csv_valid?(str)
      begin
        csv = Import.parse_csv_str(str, col_sep: upload_params[:col_sep])
        return false if csv.headers.empty?
        return false if csv.count == 0
        true
      rescue CSV::MalformedCSVError
        false
      end
    end

    def upload_params
      params.require(:import).permit(:raw_file_str, :csv_file, :col_sep)
    end
end
