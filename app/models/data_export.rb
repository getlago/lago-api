class DataExport < ApplicationRecord
  EXPORT_FORMATS = %w[csv].freeze
  STATUSES = %w[pending processing completed failed].freeze
  EXPIRATION_PERIOD = 7.days

  belongs_to :organization
  belongs_to :membership

  has_one_attached :file

  validates :resource_type, :resource_query, presence: true
  validates :format, presence: true, inclusion: {in: EXPORT_FORMATS}
  validates :status, presence: true, inclusion: {in: STATUSES}

  enum format: EXPORT_FORMATS
  enum status: STATUSES

  delegate :user, to: :membership

  def processing!
    update!(status: 'processing', started_at: Time.zone.now)
  end

  def completed!
    update!(
      status: 'completed',
      completed_at: Time.zone.now,
      expires_at: EXPIRATION_PERIOD.from_now
    )
  end

  def expired?
    return false unless expires_at

    expires_at < Time.zone.now
  end

  def filename
    return if file.blank?

    "#{created_at.strftime("%Y%m%d%H%M%S")}_#{resource_type}.#{format}"
  end

  def file_url
    return if file.blank?

    blob_path = Rails.application.routes.url_helpers.rails_blob_path(
      file,
      host: 'void',
      expires_in: 7.days
    )

    File.join(ENV['LAGO_API_URL'], blob_path)
  end
end
