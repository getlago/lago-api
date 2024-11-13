# frozen_string_literal: true

module Invoices
  class RefreshDraftAndFinalizeService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') if invoice.nil?
      return result unless invoice.draft?
      drafted_issuing_date = invoice.issuing_date

      ActiveRecord::Base.transaction do
        invoice.issuing_date = issuing_date
        refresh_result = Invoices::RefreshDraftService.call(invoice:, context: :finalize)
        if tax_error?(refresh_result.error)
          invoice.update!(issuing_date: drafted_issuing_date)
          return refresh_result
        end
        refresh_result.raise_if_error!

        invoice.payment_due_date = payment_due_date
        Invoices::TransitionToFinalStatusService.call(invoice:)
        invoice.save!

        invoice.credit_notes.each(&:finalized!)
      end

      result.invoice = invoice.reload
      after_commit do
        unless invoice.closed?
          SendWebhookJob.perform_later('invoice.created', invoice)
          GeneratePdfAndNotifyJob.perform_later(invoice:, email: should_deliver_email?)
          Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
          Integrations::Aggregator::Invoices::Crm::CreateJob.perform_later(invoice:) if invoice.should_sync_crm_invoice?
          Invoices::Payments::CreateService.new(invoice).call
          Utils::SegmentTrack.invoice_created(invoice)
        end

        invoice.credit_notes.each do |credit_note|
          track_credit_note_created(credit_note)
          SendWebhookJob.perform_later('credit_note.created', credit_note)
          CreditNotes::GeneratePdfJob.perform_later(credit_note)
        end
      end

      result
    end

    private

    attr_accessor :invoice, :result

    def issuing_date
      @issuing_date ||= Time.current.in_time_zone(invoice.customer.applicable_timezone).to_date
    end

    def payment_due_date
      @payment_due_date ||= issuing_date + invoice.customer.applicable_net_payment_term.days
    end

    def track_credit_note_created(credit_note)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'credit_note_issued',
        properties: {
          organization_id: credit_note.organization.id,
          credit_note_id: credit_note.id,
          invoice_id: credit_note.invoice_id,
          credit_note_method: 'credit'
        }
      )
    end

    def should_deliver_email?
      License.premium? &&
        invoice.organization.email_settings.include?('invoice.finalized')
    end

    def tax_error?(error)
      return false unless error.is_a?(BaseService::ValidationFailure)

      error&.messages&.dig(:tax_error).present?
    end
  end
end
