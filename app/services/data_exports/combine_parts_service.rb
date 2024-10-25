# frozen_string_literal: true

module DataExports
  class CombinePartsService < BaseService
    def initialize(data_export:)
      @data_export = data_export

      super
    end

    def call
      result.data_export = data_export

      Tempfile.create([data_export.resource_type, ".#{data_export.format}"]) do |tempfile|
        tempfile.write(data_export.export_class.headers.join(','))
        tempfile.write("\n")

        # Note the order here, this is crucial to make sure the data is in the expected order
        data_export.data_export_parts.order(:index).find_each { |part| tempfile.write(part.csv_lines) }

        tempfile.rewind

        data_export.file.attach(
          io: tempfile,
          filename: data_export.filename,
          key: "data_exports/#{data_export.id}.#{data_export.format}",
          content_type: "text/csv"
        )
      end

      data_export.completed!
      DataExportMailer.with(data_export:).completed.deliver_later

      result
    end

    private

    attr_reader :data_export
  end
end
