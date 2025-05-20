# frozen_string_literal: true

module Resolvers
  module UsageMonitoring
    class SubscriptionAlertsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "subscriptions:view"

      description "Query alerts of a subscription"

      argument :subscription_external_id, String, required: true, description: "External id of a subscription"

      argument :limit, Integer, required: false
      argument :page, Integer, required: false

      type Types::UsageMonitoring::Alerts::Object.collection_type, null: false

      def resolve(subscription_external_id:, limit: nil, page: nil)
        result = ::UsageMonitoring::AlertsQuery.call(
          organization: current_organization,
          filters: {
            subscription_external_id:
          },
          pagination: {
            page:,
            limit:
          }
        )

        result.alerts
      end
    end
  end
end
