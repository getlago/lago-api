# frozen_string_literal: true

module Resolvers
  module UsageMonitoring
    class SubscriptionAlertsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "subscriptions:view"

      description "Query alerts of a subscription"

      argument :subscription_external_id, String, required: true, description: "External id of a subscription"

      type Types::UsageMonitoring::Alerts::Object.collection_type, null: true

      def resolve(subscription_external_id:)
        alerts = current_organization.alerts.where(subscription_external_id:)
        Kaminari.paginate_array(alerts)
      end
    end
  end
end
