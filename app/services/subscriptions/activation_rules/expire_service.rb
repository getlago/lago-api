# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class ExpireService < BaseService
      Result = BaseResult[:subscription]

      def initialize(subscription:)
        @subscription = subscription
        super
      end

      def call
        result.subscription = subscription
        # The clock enqueued this against an earlier state: VIES may have resolved and restarted the timeout since.
        return result unless Subscription.expirable.exists?(id: subscription.id)

        cancel_result = CancelService.call(
          subscription:,
          rule_status: :expired,
          cancellation_reason: :timeout
        )

        if cancel_result.failure?
          return result if subscription_already_resolved?(cancel_result)

          cancel_result.raise_if_error!
        end

        result.subscription = cancel_result.subscription
        result
      end

      private

      attr_reader :subscription

      def subscription_already_resolved?(cancel_result)
        cancel_result.error.is_a?(BaseService::ValidationFailure) &&
          cancel_result.error.messages == {subscription: ["subscription_already_resolved"]}
      end
    end
  end
end
