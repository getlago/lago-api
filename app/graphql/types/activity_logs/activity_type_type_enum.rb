# frozen_string_literal: true

module Types
  module ActivityLogs
    class ActivityTypeTypeEnum < Types::BaseEnum
      description "Activity Logs Types type enums"

      Clickhouse::ActivityLog::ACTIVITY_TYPES.each do |key, value|
        value key, value:, description: value
      end
    end
  end
end
