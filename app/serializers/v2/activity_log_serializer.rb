# frozen_string_literal: true

module V2
  class ActivityLogSerializer < ModelSerializer
    timestamps :logged_at, :created_at

    def serialize
      {
        activity_id: model.activity_id,
        activity_type: model.activity_type,
        activity_source: model.activity_source,
        activity_object: parse_json_values(model.activity_object),
        activity_object_changes: parse_json_values(model.activity_object_changes),
        user_email: model.user&.email,
        resource_id: model.resource_id,
        resource_type: model.resource_type,
        external_customer_id: model.external_customer_id,
        external_subscription_id: model.external_subscription_id
      }
    end

    private

    # ClickHouse stores these fields as a map of JSON-encoded strings. We parse
    # one level deep only, to match app/graphql/types/activity_logs/object.rb; a
    # value nested inside an already-parsed object stays encoded, as in GraphQL.
    # A non-JSON value (or one that does not parse to an Array/Hash) is returned
    # unchanged. Do not deepen this past one level.
    def parse_json_values(map)
      map.transform_values do |value|
        parsed = value.is_a?(String) ? JSON.parse(value) : value
        (parsed.is_a?(Array) || parsed.is_a?(Hash)) ? parsed : value
      rescue JSON::ParserError
        value
      end
    end
  end
end
