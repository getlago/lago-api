# frozen_string_literal: true

module Resolvers
  class ActivityLogsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "activity_logs:view"

    description "Query activity logs of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    argument :from_date, GraphQL::Types::ISO8601Date, required: false
    argument :to_date, GraphQL::Types::ISO8601Date, required: false
    argument :activity_types, [String], required: false
    argument :activity_sources, [Types::ActivityLogs::ActivitySourceTypeEnum], required: false
    argument :api_key_ids, [String], required: false
    argument :external_customer_id, String, required: false
    argument :external_subscription_id, String, required: false
    argument :resource_id, String, required: false
    argument :resource_type, String, required: false
    argument :user_emails, [String], required: false

    type Types::Taxes::Object, null: true

    def resolve(id: nil)
      current_organization.activity_logs.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "activity_log")
    end
  end
end
