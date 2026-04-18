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
          rule.evaluate!
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

        if all_rules_satisfied?
          Subscriptions::ActivateService.call!(subscription:)
        elsif any_rule_failed?
          subscription.mark_as_canceled!
          SendWebhookJob.perform_after_commit("subscription.canceled", subscription)
        end
      end

      def all_rules_satisfied?
        subscription.activation_rules.all? { |rule| rule.satisfied? || rule.not_applicable? }
      end

      def any_rule_failed?
        subscription.activation_rules.any? { |rule| rule.failed? || rule.expired? || rule.declined? }
      end
    end
  end
end
