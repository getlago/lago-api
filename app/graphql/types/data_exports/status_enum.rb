# frozen_string_literal: true

module Types
  module DataExports
    class StatusEnum < Types::BaseEnum
      DataExport::STATUSES.each do |status|
        value status
      end
    end
  end
end
