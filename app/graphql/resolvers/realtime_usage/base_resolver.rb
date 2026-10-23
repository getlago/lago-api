# frozen_string_literal: true

module Resolvers
  module RealtimeUsage
    # The filters every real-time usage report shares.
    class BaseResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "analytics:view"

      argument :external_customer_id, String, required: false
      argument :external_subscription_id, String, required: false
      argument :from_datetime, GraphQL::Types::ISO8601DateTime, required: false
      argument :to_datetime, GraphQL::Types::ISO8601DateTime, required: false

      private

      # Deleted customers and terminated subscriptions keep their buckets, so the filters match
      # every record the external id named.
      def report_filters(external_customer_id: nil, external_subscription_id: nil, from_datetime: nil, to_datetime: nil)
        {
          organization: current_organization,
          customer_ids: external_customer_id &&
            Customer.with_discarded.where(organization: current_organization, external_id: external_customer_id).ids,
          subscription_ids: external_subscription_id &&
            current_organization.subscriptions.where(external_id: external_subscription_id).ids,
          from_datetime:,
          to_datetime:
        }
      end
    end
  end
end
