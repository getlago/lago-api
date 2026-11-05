# frozen_string_literal: true

module Types
  module RealtimeUsage
    class TimeGranularityEnum < Types::BaseEnum
      graphql_name "RealtimeUsageTimeGranularityEnum"

      value "hour"
      value "day"
    end
  end
end
