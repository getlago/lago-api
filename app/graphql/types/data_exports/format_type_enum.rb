# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module DataExports
    class FormatTypeEnum < Types::BaseEnum
      graphql_name "DataExportFormatTypeEnum"

      DataExport::EXPORT_FORMATS.each do |format|
        value format
      end
    end
  end
end
