# frozen_string_literal: true

module Invoices
  module Preview
    class FindSubscriptionsService < BaseService
      Result = BaseResult[:subscriptions]

      def initialize(subscriptions:)
        @subscriptions = subscriptions
        super
      end

      def call
        return result.not_found_failure!(resource: "subscription") if subscriptions.empty?

        result.subscriptions = subscriptions.flat_map do |subscription|
          if subscription.next_subscription
            [
              terminated_subscription(subscription),
              (adjusted_next_subscription(subscription) if subscription.next_subscription.plan.pay_in_advance?)
            ].compact
          else
            subscription
          end
        end

        result
      end

      private

      attr_reader :subscriptions

      def terminated_subscription(subscription)
        subscription.terminated_at = termination_date(subscription)
        subscription.status = :terminated

        subscription.next_subscriptions.build(
          **adjusted_next_subscription(subscription).attributes
        )

        subscription
      end

      def adjusted_next_subscription(subscription)
        subscription.next_subscription.assign_attributes(
          status: :active,
          started_at: subscription.upgraded? ? Time.current : termination_date(subscription),
        )

        subscription.next_subscription
      end

      def termination_date(subscription)
        @termination_date ||= if subscription.upgraded?
          Time.current
        else
          Subscriptions::DatesService
            .new_instance(subscription, Time.current, current_usage: true)
            .end_of_period + 1.day
        end
      end
    end
  end
end
