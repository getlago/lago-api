# frozen_string_literal: true

module Invoices
  module PayInAdvance
    class BaseService < ::BaseService
      ACQUIRE_LOCK_TIMEOUT = 5.seconds
      private_constant :ACQUIRE_LOCK_TIMEOUT

      private

      attr_accessor :invoice

      def customer_lock_key
        "customer-#{customer.id}"
      end

      def deliver_webhooks
        invoice.fees.each { |f| SendWebhookJob.perform_later("fee.created", f) }
        SendWebhookJob.perform_later("invoice.created", invoice)
      end

      def should_deliver_email?
        License.premium? && customer.billing_entity.email_settings.include?("invoice.finalized")
      end

      def should_create_applied_prepaid_credit?
        invoice.total_amount_cents&.positive?
      end

      def create_credit_note_credit
        credit_result = Credits::CreditNoteService.new(invoice:).call
        credit_result.raise_if_error!

        refresh_amounts(credit_amount_cents: credit_result.credits.sum(&:amount_cents)) if credit_result.credits
      end

      def create_applied_prepaid_credit
        # We don't actually want to retry. We let it fail and let the job be retried through ActiveJob retry mechanism.
        prepaid_credit_result = Credits::AppliedPrepaidCreditsService.call!(invoice:, max_wallet_decrease_attempts: 1)
        refresh_amounts(credit_amount_cents: prepaid_credit_result.prepaid_credit_amount_cents)
      end

      def refresh_amounts(credit_amount_cents:)
        invoice.total_amount_cents -= credit_amount_cents
      end

      def apply_fees_and_coupons
        invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
        invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents
        Credits::AppliedCouponsService.call(invoice:) if invoice.fees_amount_cents&.positive?
      end

      def apply_credits
        create_credit_note_credit
        create_applied_prepaid_credit if should_create_applied_prepaid_credit?
        Invoices::ApplyInvoiceCustomSectionsService.call(invoice:)
      end

      def finalize_invoice
        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        Invoices::TransitionToFinalStatusService.call(invoice:)
        invoice.save!
      end

      def trigger_post_creation_jobs
        return if invoice.closed?

        Utils::SegmentTrack.invoice_created(invoice)
        deliver_webhooks
        Utils::ActivityLog.produce(invoice, "invoice.created")
        Invoices::GenerateDocumentsJob.perform_later(invoice:, notify: should_deliver_email?)
        Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
        Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?
        Invoices::Payments::CreateService.call_async(invoice:)
      end
    end
  end
end
