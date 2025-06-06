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
          if subscription.downgraded?
            sub = adjusted_subscription(subscription)

            [
              sub,
              (sub.next_subscription if sub.next_subscription.plan.pay_in_advance?)
            ].compact
          else
            subscription
          end
        end

        result
      end

      private

      attr_reader :subscriptions

      def adjusted_subscription(subscription)
        subscription.terminated_at = rotation_date(subscription)
        subscription.status = :terminated

        subscription.next_subscription.assign_attributes(
          status: :active,
          started_at: rotation_date(subscription)
        )

        subscription
      end

      def rotation_date(subscription)
        @rotation_date ||= Subscriptions::DatesService
          .new_instance(subscription, Time.current, current_usage: true)
          .end_of_period + 1.day
      end
    end
  end
end
