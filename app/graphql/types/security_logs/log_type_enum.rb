# frozen_string_literal: true

module Types
  module SecurityLogs
    class LogTypeEnum < Types::BaseEnum
      description "Security Log type"

      Clickhouse::SecurityLog::LOG_TYPES.each do |key, value|
        value key, value:, description: value
      end
    end
  end
end
