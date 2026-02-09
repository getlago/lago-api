# frozen_string_literal: true

module Invoices
  class FinalizePendingViesInvoiceService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:)
      @invoice = invoice

      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice
      return result unless invoice.pending? && invoice.tax_pending?
      return result if customer.tax_customer
      return result if customer.vies_check_in_progress?

      ActiveRecord::Base.transaction do
        invoice.issuing_date = issuing_date
        invoice.payment_due_date = payment_due_date

        Invoices::ComputeAmountsFromFees.call(invoice:)
        Invoices::ApplyInvoiceCustomSectionsService.call(invoice:)

        create_credit_note_credit if should_create_credit_note_credit?
        create_applied_prepaid_credit if should_create_applied_prepaid_credit?

        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        invoice.tax_status = "succeeded"
        Invoices::TransitionToFinalStatusService.call(invoice:)

        invoice.save!
        invoice.reload

        result.invoice = invoice
      end

      if invoice.finalized?
        after_commit do
          SendWebhookJob.perform_later("invoice.created", invoice)
          Utils::ActivityLog.produce(invoice, "invoice.created")
          GenerateDocumentsJob.perform_later(invoice:, notify: should_deliver_email?)
          Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
          Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?
          Invoices::Payments::CreateService.call_async(invoice:)
          Utils::SegmentTrack.invoice_created(invoice)
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice

    def customer
      @customer ||= invoice.customer
    end

    def issuing_date
      @issuing_date ||= if issuing_date_keep_anchor?
        invoice.issuing_date
      else
        Time.current.in_time_zone(customer.applicable_timezone).to_date
      end
    end

    def issuing_date_keep_anchor?
      invoice.invoice_subscriptions.first&.recurring? &&
        customer.applicable_subscription_invoice_issuing_date_adjustment == "keep_anchor"
    end

    def payment_due_date
      @payment_due_date ||= issuing_date + customer.applicable_net_payment_term.days
    end

    def should_create_credit_note_credit?
      !invoice.one_off?
    end

    def should_create_applied_prepaid_credit?
      return false if invoice.one_off?

      invoice.total_amount_cents&.positive?
    end

    def create_credit_note_credit
      credit_result = Credits::CreditNoteService.new(invoice:).call!
      invoice.total_amount_cents -= credit_result.credits.sum(&:amount_cents) if credit_result.credits
    end

    def create_applied_prepaid_credit
      prepaid_credit_result = Credits::AppliedPrepaidCreditsService.call!(invoice:)
      invoice.total_amount_cents -= prepaid_credit_result.prepaid_credit_amount_cents
    end

    def should_deliver_email?
      License.premium? &&
        invoice.billing_entity.email_settings.include?("invoice.finalized")
    end
  end
end
