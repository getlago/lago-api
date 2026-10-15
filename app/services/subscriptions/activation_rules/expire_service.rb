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
        cancel_result = CancelService.call(
          subscription:,
          rule_status: :expired,
          cancellation_reason: :timeout
        )

        if cancel_result.failure?
          if subscription_already_resolved?(cancel_result)
            result.subscription = subscription
            return result
          end

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
