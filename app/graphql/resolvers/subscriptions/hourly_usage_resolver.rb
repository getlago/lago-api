# frozen_string_literal: true

module Resolvers
  module Subscriptions
    # Realtime usage of one charge, per hour and per charge filter, read
    # from the RisingWave-fed 15-minute buckets. Meant to be polled while
    # the usage tab is open: the last hour of the window is still filling.
    class HourlyUsageResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "customers:view"

      description "Query the hourly usage of a subscription charge, broken down by charge filter"

      argument :charge_id, type: ID, required: true
      argument :from_datetime, type: GraphQL::Types::ISO8601DateTime, required: false
      argument :subscription_id, type: ID, required: true
      argument :to_datetime, type: GraphQL::Types::ISO8601DateTime, required: false

      type Types::Subscriptions::RealtimeUsage::Hourly, null: false

      def resolve(subscription_id:, charge_id:, from_datetime: nil, to_datetime: nil)
        subscription = current_organization.subscriptions.find(subscription_id)
        charge = subscription.plan.charges.find(charge_id)

        result = ::RealtimeUsage::HourlyBreakdownService.call(
          subscription:,
          charge:,
          from_datetime:,
          to_datetime:
        )

        result.success? ? result.usage : result_error(result)
      rescue ActiveRecord::RecordNotFound => e
        not_found_error(resource: (e.model == "Charge") ? "charge" : "subscription")
      end
    end
  end
end
