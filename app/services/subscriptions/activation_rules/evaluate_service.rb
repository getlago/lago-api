# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class EvaluateService < BaseService
      Result = BaseResult[:subscription, :rules]

      def initialize(subscription:)
        @subscription = subscription
        super
      end

      def call
        result.rules = []

        subscription.activation_rules.each do |rule|
          case rule
          when Subscription::ActivationRule::Payment
            Payment::EvaluateService.call!(rule:)
          end
          result.rules << rule
        end

        resolve_subscription_status

        result.subscription = subscription
        result
      end

      private

      attr_reader :subscription

      def resolve_subscription_status
        return unless subscription.incomplete?

        if subscription.activation_rules.any?(&:failed?)
          subscription.mark_as_canceled!

          after_commit do
            SendWebhookJob.perform_later("subscription.canceled", subscription)
          end
        elsif !subscription.pending_rules?
          Subscriptions::ActivateService.call!(subscription:)
        end
      end
    end
  end
end
