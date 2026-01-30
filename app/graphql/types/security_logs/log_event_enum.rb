# frozen_string_literal: true

module Types
  module SecurityLogs
    class LogEventEnum < Types::BaseEnum
      description "Security Log event"

      # More events will be added as event integrations are implemented
      value "user_signed_up", value: "user.signed_up", description: "User signed up"
    end
  end
end
