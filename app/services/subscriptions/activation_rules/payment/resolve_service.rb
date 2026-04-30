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
          ActivationRules::ResolveSubscriptionStatusService.call!(subscription:)

          after_commit do
            SendWebhookJob.perform_later("invoice.created", invoice)
            Utils::ActivityLog.produce(invoice, "invoice.created")
            Invoices::GenerateDocumentsJob.perform_later(invoice:, notify: should_deliver_email?)
            Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
            Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?
            Utils::SegmentTrack.invoice_created(invoice)
          end
        end

        def handle_failure
          return unless subscription.incomplete? && invoice.open? && invoice.subscription?

          EvaluateService.call!(rule: payment_rule, status: :failed)
          invoice.closed!
          ActivationRules::ResolveSubscriptionStatusService.call!(subscription:)
          subscription.update!(cancelation_reason: :payment_failed)
        end

        def payment_rule
          @payment_rule ||= subscription.activation_rules.payment.sole
        end

        def should_deliver_email?
          License.premium? &&
            invoice.billing_entity.email_settings.include?("invoice.finalized")
        end
      end
    end
  end
end
