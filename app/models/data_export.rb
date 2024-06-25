class DataExport < ApplicationRecord
  EXPORT_FORMATS = %w[csv].freeze
  STATUSES = %w[pending processing completed failed].freeze

  belongs_to :user
  has_one_attached :file

  validates :resource_type, :resource_query, presence: true
  validates :format, presence: true, inclusion: {in: EXPORT_FORMATS}
  validates :status, presence: true, inclusion: {in: STATUSES}

  enum format: EXPORT_FORMATS
  enum status: STATUSES
end
