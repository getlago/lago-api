# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module SecurityLogs
    class LogEventEnum < Types::BaseEnum
      description "Security Log event"

      Clickhouse::SecurityLog::LOG_EVENTS.each do |event|
        value event.tr(".", "_"), value: event, description: event
      end
    end
  end
end
