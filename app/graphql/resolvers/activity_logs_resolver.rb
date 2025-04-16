# frozen_string_literal: true

module Resolvers
  class ActivityLogsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "activity_logs:view"

    description "Query activity logs of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    argument :activity_sources, [Types::ActivityLogs::ActivitySourceTypeEnum], required: false
    argument :activity_types, [String], required: false
    argument :api_key_ids, [String], required: false
    argument :external_customer_id, String, required: false
    argument :external_subscription_id, String, required: false
    argument :from_date, GraphQL::Types::ISO8601Date, required: false
    argument :resource_id, String, required: false
    argument :resource_type, String, required: false
    argument :to_date, GraphQL::Types::ISO8601Date, required: false
    argument :user_emails, [String], required: false

    type Types::ActivityLogs::Object, null: true

    def resolve(**args)
      # TODO: Still need to define the query for the ActivityLogs.
    end
  end
end
