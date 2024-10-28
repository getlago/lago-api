# frozen_string_literal: true

module DataExports
  class CreatePartService < BaseService
    def initialize(data_export:, object_ids:, index:)
      @data_export = data_export
      @object_ids = object_ids
      @index = index

      super
    end

    def call
      result.data_export_part = data_export.data_export_parts.create!(object_ids:, index:)
      after_commit { DataExports::ProcessPartJob.perform_later(result.data_export_part) }
      result
    rescue => e
      result.service_failure!(code: 'data_export_part_creation_failed', message: e.full_message)
    end

    private

    attr_reader :data_export, :object_ids, :index
  end
end
