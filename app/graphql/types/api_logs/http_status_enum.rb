# frozen_string_literal: true

module Types
  module ApiLogs
    class HttpStatusEnum < Types::BaseEnum
      description "Api Logs http status enums"

      value "success", 1, description: "Success"
      value "error", 2, description: "Error"
    end
  end
end
