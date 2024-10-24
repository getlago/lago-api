# frozen_string_literal: true

module DataExports
  class ProcessPartJob < ApplicationJob
    queue_as :low_priority

    def perform(data_export_part)
      ProcessPartService.call(data_export_part:).raise_if_error!
    end
  end
end
