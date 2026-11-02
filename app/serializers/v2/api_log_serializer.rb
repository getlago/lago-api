# frozen_string_literal: true

module V2
  class ApiLogSerializer < ModelSerializer
    timestamps :logged_at, :created_at

    def serialize
      {
        request_id: model.request_id,
        client: model.client,
        http_method: model.http_method,
        http_status: model.http_status,
        request_origin: model.request_origin,
        request_path: model.request_path,
        request_body: deep_json_parser(model.request_body),
        request_response: deep_json_parser(model.request_response),
        api_version: model.api_version
      }
    end

    private

    # Parses the ClickHouse map values one level deep, matching the GraphQL
    # layer (app/graphql/types/api_logs/object.rb): only String values are
    # parsed, the result is kept only when it is an Array or Hash, and a value
    # that is not valid JSON is returned unchanged.
    def deep_json_parser(attribute)
      attribute.transform_values do |value|
        parsed = value.is_a?(String) ? JSON.parse(value) : value
        (parsed.is_a?(Array) || parsed.is_a?(Hash)) ? parsed : value
      rescue JSON::ParserError
        value
      end
    end
  end
end
