# frozen_string_literal: true

module Types
  module SecurityLogs
    class LogTypeEnum < Types::BaseEnum
      description "Security Log type"

      # More values will be added as event integrations are implemented
      value "user", value: "user", description: "User events"
    end
  end
end
