# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module DataExports
    class StatusEnum < Types::BaseEnum
      graphql_name "DataExportStatusEnum"

      DataExport::STATUSES.each do |status|
        value status
      end
    end
  end
end
