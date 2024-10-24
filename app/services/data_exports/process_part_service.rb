# frozen_string_literal: true

module DataExports
  class ProcessPartService
    def initialize(data_export_part:)
      super(nil)

      @data_export_part = data_export_part
      @data_export = data_export_part.data_export
    end

    def call
      result.data_export_part = data_export_part

      data_export_part.transaction do
        # produce CSV lines into StringIO
        output = StringIO.new
        data_export.export_class.call(data_export_part:, output:).raise_if_error!

        data_export_part.update!(csv_lines: output, completed: true)
      end

      # check if we are the last one to finish
      if last_completed
        DataExports::CombinePartsJob.perform_later(data_export_part.data_export)
      end
    end

    private

    attr_reader :data_export_part, :data_export

    def last_completed
      data_export.data_export_parts.completed.count == data_export.data_export_parts.count
    end
  end
end
