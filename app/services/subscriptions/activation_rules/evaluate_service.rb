# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class EvaluateService < BaseService
      Result = BaseResult[:has_applicable_rules]

      def initialize(subscription:)
        @subscription = subscription

        super
      end

      def call
        rules = subscription.activation_rules

        return result if rules.empty?

        return result unless validate_rules(rules)

        rules.each do |rule|
          if applicable?(rule)
            rule.update!(
              status: "pending",
              expires_at: compute_expires_at(rule)
            )
          else
            rule.update!(status: "not_applicable")
          end
        end

        result.has_applicable_rules = rules.any? { |r| r.status == "pending" }
        result
      end

      private

      attr_reader :subscription

      def validate_rules(rules)
        rules.each do |rule|
          case rule.rule_type
          when "payment_required"
            if subscription.customer.payment_provider.blank?
              result.single_validation_failure!(
                field: :activation_rules,
                error_code: "payment_provider_required_for_payment_rule"
              )
              return false
            end
          end
        end

        true
      end

      def applicable?(rule)
        case rule.rule_type
        when "payment_required"
          payment_rule_applicable?
        else
          false
        end
      end

      def payment_rule_applicable?
        has_upfront_billing = (subscription.plan.pay_in_advance? && !subscription.in_trial_period?) ||
          subscription.fixed_charges.pay_in_advance.any?

        return false unless has_upfront_billing

        true
      end

      def compute_expires_at(rule)
        return nil if rule.timeout_hours.blank?

        Time.current + rule.timeout_hours.hours
      end
    end
  end
end
