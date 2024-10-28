# frozen_string_literal: true

module DataExports
  class ProcessPartService < BaseService
    def initialize(data_export_part:)
      @data_export_part = data_export_part
      @data_export = data_export_part.data_export
      super(nil)
    end

    def call
      result.data_export_part = data_export_part

      # produce CSV lines into StringIO
      export_result = data_export.export_class.call(data_export_part:).raise_if_error!
      data_export_part.update!(csv_lines: export_result.csv_lines, completed: true)

      # check if we are the last one to finish
      if last_completed
        after_commit { DataExports::CombinePartsJob.perform_later(data_export_part.data_export) }
      end
      result
    end

    private

    attr_reader :data_export_part, :data_export

    def last_completed
      data_export.data_export_parts.completed.count == data_export.data_export_parts.count
    end
  end
end
