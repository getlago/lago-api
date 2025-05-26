# frozen_string_literal: true

module Resolvers
  class ActivityLogsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "audit_logs:view"

    description "Query activity logs of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    argument :activity_ids, [String], required: false
    argument :activity_sources, [Types::ActivityLogs::ActivitySourceEnum], required: false
    argument :activity_types, [Types::ActivityLogs::ActivityTypeEnum], required: false
    argument :api_key_ids, [String], required: false
    argument :external_customer_id, String, required: false
    argument :external_subscription_id, String, required: false
    argument :from_date, GraphQL::Types::ISO8601Date, required: false
    argument :resource_ids, [String], required: false
    argument :resource_types, [Types::ActivityLogs::ResourceTypeEnum], required: false
    argument :to_date, GraphQL::Types::ISO8601Date, required: false
    argument :user_emails, [String], required: false

    type Types::ActivityLogs::Object.collection_type, null: true

    def resolve(**args)
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
