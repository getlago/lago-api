# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module DataExports
  class ProcessPartJob < ApplicationJob
    queue_as :default

    def perform(data_export_part)
      ProcessPartService.call(data_export_part:).raise_if_error!
    end
  end
end
