# frozen_string_literal: true

module Types
  module ApiLogs
    class Object < Types::BaseObject
      graphql_name "ApiLog"
      description "Base api log"

      field :api_key, Types::ApiKeys::SanitizedObject
      field :api_version, String
      field :client, String
      field :http_method, Types::ApiLogs::HttpMethodEnum
      field :http_status, Integer
      field :request_body, GraphQL::Types::JSON
      field :request_id, ID, null: false
      field :request_origin, String
      field :request_path, String
      field :request_response, GraphQL::Types::JSON

      field :created_at, GraphQL::Types::ISO8601DateTime
      field :logged_at, GraphQL::Types::ISO8601DateTime
    end
  end
end
