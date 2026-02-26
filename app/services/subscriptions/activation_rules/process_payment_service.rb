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
        return result unless subscription&.activating?

        rule = subscription.activation_rules.find_by(rule_type: "payment_required")
        return result unless rule&.status&.in?(%w[pending failed])

        if payment_status == :succeeded
          rule.update!(status: "satisfied")
          TryActivateService.call!(subscription:, invoice:)
        else
          rule.update!(status: "failed")
        end

        result
      end

      private

      attr_reader :invoice, :payment_status
    end
  end
end
