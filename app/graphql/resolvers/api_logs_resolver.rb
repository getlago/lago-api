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
    argument :http_statuses, [Types::ApiLogs::HttpStatus], required: false
    argument :request_ids, [String], required: false
    argument :request_paths, [String], required: false

    type Types::ApiLogs::Object.collection_type, null: true

    def resolve(**args)
      raise unauthorized_error unless License.premium?

      result = ApiLogsQuery.call(
        organization: current_organization,
        filters: {
          from_date: args[:from_date],
          to_date: args[:to_date],
          api_key_ids: args[:api_key_ids],
          request_ids: args[:request_ids],
          http_statuses: args[:http_statuses],
          http_methods: args[:http_methods],
          api_version: args[:api_version],
          request_paths: args[:request_paths]
        },
        pagination: {
          page: args[:page],
          limit: args[:limit]
        }
      )

      result.api_logs
    end
  end
end
