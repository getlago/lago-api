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
          return unless subscription.incomplete? && invoice.open? && invoice.subscription?

          EvaluateService.call!(rule: payment_rule, status: :satisfied)
          Invoices::FinalizeService.call!(invoice:)
          ActivationRules::EvaluateService.call!(subscription:)
        end

        def handle_failure
          return unless subscription.incomplete? && invoice.open? && invoice.subscription?

          EvaluateService.call!(rule: payment_rule, status: :failed)
          invoice.closed!
          subscription.cancelation_reason = :payment_failed
          ActivationRules::EvaluateService.call!(subscription:)
        end

        def payment_rule
          @payment_rule ||= subscription.activation_rules.payment.sole
        end
      end
    end
  end
end
