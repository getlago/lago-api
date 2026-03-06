# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class ProcessPaymentService < BaseService
      def initialize(invoice:, payment_status:)
        @invoice = invoice
        @payment_status = payment_status.to_sym

        super
      end

      def call
        subscription = invoice.subscriptions.first
        return result unless subscription

        if subscription.activating?
          handle_activating_subscription(subscription)
        elsif payment_status == :succeeded && subscription_no_longer_activating?(subscription)
          handle_late_payment_success
        end

        result
      end

      private

      attr_reader :invoice, :payment_status

      def handle_activating_subscription(subscription)
        rule = subscription.activation_rules.find_by(rule_type: "payment_required")
        return unless rule&.status&.in?(%w[pending failed])

        if payment_status == :succeeded
          rule.update!(status: "satisfied")
          TryActivateService.call!(subscription:, invoice:)
        else
          rule.update!(status: "failed")
        end
      end

      def subscription_no_longer_activating?(subscription)
        subscription.canceled? || subscription.terminated?
      end

      def handle_late_payment_success
        RefundExpiredPaymentService.call!(invoice:)
      end
    end
  end
end
