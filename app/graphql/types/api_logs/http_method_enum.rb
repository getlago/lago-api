# frozen_string_literal: true

module Types
  module ApiLogs
    class HttpMethodEnum < Types::BaseEnum
      description "Api Logs http method enums"

      Clickhouse::ApiLog::HTTP_METHODS.each do |key, value|
        value key, value:, description: "#{key} request"
      end
    end
  end
end
