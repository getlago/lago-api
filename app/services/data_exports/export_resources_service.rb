module DataExports
  class ExportResourcesService < BaseService
    EXPIRED_FAILURE_MESSAGE = 'Data Export already expired'
    PROCESSED_FAILURE_MESSAGE = 'Data Export already processed'

    def initialize(data_export:)
      @data_export = data_export

      super
    end

    def call
      return result.service_failure!(code: 'data_export_expired', message: EXPIRED_FAILURE_MESSAGE) if data_export.expired?
      return result.service_failure!(code: 'data_export_processed', message: PROCESSED_FAILURE_MESSAGE) unless data_export.pending?

      data_export.processing!

      data_export.file.attach(
        io: StringIO.new(file_data),
        filename:,
        key: data_export.membership_id,
        content_type:
      )

      data_export.completed!

      DataExportMailer.with(data_export:).completed.deliver_later

      result.data_export = data_export
      result
    rescue => e
      data_export.failed!
      result.service_failure!(code: e.message, message: e.full_message)
    end

    private

    attr_reader :data_export

    def file_data
      case data_export.resource_type
      when "invoices" then Csv::Invoices.call(data_export:)
      end
    end

    def filename
      "#{data_export.resource_type}_export_#{Time.zone.now.to_i}.#{data_export.format}"
    end

    def content_type
      'text/csv'
    end
  end
end
