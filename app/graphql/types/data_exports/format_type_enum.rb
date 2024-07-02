# frozen_string_literal: true

module Types
  module DataExports
    class FormatTypeEnum < Types::BaseEnum
      DataExport::EXPORT_FORMATS.each do |format|
        value format
      end
    end
  end
end
