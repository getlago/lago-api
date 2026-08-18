# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    # Re-derives the periods of every subscription affected by a change to an input they share: the
    # applicable timezone of a customer or of a billing entity.
    #
    # The plan is not one of them: its interval and monthly-charges flag would move the boundaries,
    # but a plan attached to a subscription refuses both.
    class RefreshAllService < BaseService
      Result = BaseResult[:enqueued_count]

      def initialize(owner:)
        @owner = owner

        super
      end

      def call
        # Resolved first so an unsupported owner is rejected whether the flag is on or off.
        scope = subscriptions

        result.enqueued_count = 0
        return result if organization.feature_flag_disabled?(:subscription_billing_periods)

        count = 0

        scope.find_each do |subscription|
          Subscriptions::BillingPeriods::UpsertJob.perform_later(subscription.id)
          count += 1
        end

        result.enqueued_count = count
        result
      end

      private

      attr_reader :owner

      def organization
        @organization ||= owner.organization
      end

      def subscriptions
        scope = case owner
        when Customer then Subscription.where(customer_id: owner.id)
        when BillingEntity then Subscription.joins(:customer).where(customers: {billing_entity_id: owner.id})
        else raise ArgumentError, "unsupported owner: #{owner.class}"
        end

        scope.where(status: %i[active terminated])
      end
    end
  end
end
