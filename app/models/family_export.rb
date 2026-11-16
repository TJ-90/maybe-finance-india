class FamilyExport < ApplicationRecord
  belongs_to :family

  has_one_attached :export_file

  enum :status, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :pending, validate: true

  scope :ordered, -> { order(created_at: :desc) }

  def filename
    "#{Rails.application.config.x.product_name.parameterize(separator: "_")}_export_#{created_at.utc.strftime('%Y%m%d_%H%M%S')}.zip"
  end

  def downloadable?
    completed? && export_file.attached?
  end
end
