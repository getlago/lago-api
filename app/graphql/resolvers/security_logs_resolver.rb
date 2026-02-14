# frozen_string_literal: true

module Resolvers
  class SecurityLogsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "security_logs:view"

    description "Query security logs of an organization"

    argument :from_datetime, GraphQL::Types::ISO8601DateTime, required: false
    argument :limit, Integer, required: false
    argument :log_events, [Types::SecurityLogs::LogEventEnum], required: false
    argument :log_types, [Types::SecurityLogs::LogTypeEnum], required: false
    argument :page, Integer, required: false
    argument :to_datetime, GraphQL::Types::ISO8601DateTime, required: true,
      description: "Upper date boundary (required for consistent pagination)"
    argument :user_ids, [ID], required: false

    type Types::SecurityLogs::Object.collection_type, null: true

    def resolve(**args)
      result = SecurityLogsQuery.call(
        organization: current_organization,
        filters: {
          from_date: args[:from_datetime],
          to_date: args[:to_datetime],
          user_ids: args[:user_ids],
          log_types: args[:log_types],
          log_events: args[:log_events]
        },
        pagination: {
          page: args[:page],
          limit: args[:limit]
        }
      )

      return result_error(result) unless result.success?

      result.security_logs
    end
  end
end
