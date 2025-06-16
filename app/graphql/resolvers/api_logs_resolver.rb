# frozen_string_literal: true

module Resolvers
  class ApiLogsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "audit_logs:view"

    description "Query api logs of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    argument :from_date, GraphQL::Types::ISO8601Date, required: false
    argument :to_date, GraphQL::Types::ISO8601Date, required: false

    argument :api_key_ids, [String], required: false
    argument :http_methods, [Types::ApiLogs::HttpMethodEnum], required: false
    argument :http_statuses, [Types::ApiLogs::HttpStatusEnum], required: false
    argument :request_paths, [String], required: false

    type Types::ApiLogs::Object.collection_type, null: true

    def resolve(**args)
      raise unauthorized_error unless License.premium?

      result = ActivityLogsQuery.call(
        organization: current_organization,
        filters: {
          from_date: args[:from_date],
          to_date: args[:to_date],
          api_key_ids: args[:api_key_ids],
          activity_ids: args[:activity_ids],
          activity_types: args[:activity_types],
          activity_sources: args[:activity_sources],
          user_emails: args[:user_emails],
          external_customer_id: args[:external_customer_id],
          external_subscription_id: args[:external_subscription_id],
          resource_ids: args[:resource_ids],
          resource_types: args[:resource_types]
        },
        pagination: {
          page: args[:page],
          limit: args[:limit]
        }
      )

      result.activity_logs
    end
  end
end
