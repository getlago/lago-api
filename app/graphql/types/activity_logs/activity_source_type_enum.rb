# frozen_string_literal: true

module Types
  module ActivityLogs
    class ActivitySourceTypeEnum < Types::BaseEnum
      graphql_name "ActivitySourceTypeEnum"
      description "Activity Logs source type enums"

      Clickhouse::ActivityLog::SOURCES.each do |type|
        value type
      end
    end
  end
end
