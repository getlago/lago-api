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
        cancel_result = CancelService.call!(
          subscription:,
          rule_status: :expired,
          cancellation_reason: :timeout
        )

        result.subscription = cancel_result.subscription
        result
      end

      private

      attr_reader :subscription
    end
  end
end
