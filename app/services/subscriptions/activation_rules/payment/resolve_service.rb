# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    module Payment
      class ResolveService < BaseService
        Result = BaseResult

        def initialize(subscription:, invoice:, payment_status:)
          @subscription = subscription
          @invoice = invoice
          @payment_status = payment_status.to_sym
          super
        end

        def call
          subscription.with_lock do
            case payment_status
            when :succeeded
              handle_success
            when :failed
              handle_failure
            end
          end

          result
        end

        private

        attr_reader :subscription, :invoice, :payment_status

        def handle_success
          # TODO: implement in next TDD cycle
        end

        def handle_failure
          return unless subscription.incomplete? && invoice.open? && invoice.subscription?

          payment_rule.failed!
          invoice.closed!
          subscription.cancelation_reason = :payment_failed
          subscription.mark_as_canceled!

          SendWebhookJob.perform_later("subscription.canceled", subscription)
        end

        def payment_rule
          @payment_rule ||= subscription.activation_rules.find_by(type: "payment")
        end
      end
    end
  end
end
