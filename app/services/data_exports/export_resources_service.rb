# frozen_string_literal: true

module DataExports
  class ExportResourcesService < BaseService
    EXPIRED_FAILURE_MESSAGE = 'Data Export already expired'
    PROCESSED_FAILURE_MESSAGE = 'Data Export already processed'

    ResourceTypeNotSupportedError = Class.new(StandardError)

    extend Forwardable

    def_delegators :data_export, :resource_type, :format

    def initialize(data_export:)
      @data_export = data_export

      super
    end

    def call
      return result.service_failure!(code: 'data_export_expired', message: EXPIRED_FAILURE_MESSAGE) if data_export.expired?
      return result.service_failure!(code: 'data_export_processed', message: PROCESSED_FAILURE_MESSAGE) unless data_export.pending?

      data_export.processing!

      Tempfile.create([resource_type, ".#{format}"]) do |tempfile|
        generate_export(tempfile)
        tempfile.rewind

        data_export.file.attach(
          io: tempfile,
          filename:,
          key: "data_exports/#{data_export.id}.#{format}",
          content_type:
        )

        data_export.completed!
      end

      DataExportMailer.with(data_export:).completed.deliver_later

      result.data_export = data_export
      result
    rescue => e
      data_export.failed!
      result.service_failure!(code: e.message, message: e.full_message)
    end

    private

    attr_reader :data_export

    def generate_export(file)
      case resource_type
      when "invoices" then Csv::Invoices.call(data_export:, output: file)
      when "invoice_fees" then Csv::InvoiceFees.call(data_export:, output: file)
      else
        raise ResourceTypeNotSupportedError.new(
          "'#{resource_type}' resource not supported"
        )
      end
    end

    def filename
      "#{resource_type}_export_#{Time.zone.now.to_i}.#{format}"
    end

    def content_type
      'text/csv'
    end
  end
end
