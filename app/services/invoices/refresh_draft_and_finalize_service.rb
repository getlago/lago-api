# frozen_string_literal: true

module Invoices
  class RefreshDraftAndFinalizeService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') if invoice.nil?

      ActiveRecord::Base.transaction do
        Invoices::RefreshDraftService.call(invoice:, context: :finalize).raise_if_error!

        invoice.status = :finalized
        invoice.issuing_date = issuing_date
        invoice.payment_due_date = payment_due_date
        invoice.save!

        invoice.credit_notes.each(&:finalized!)
      end

      result.invoice = invoice.reload

      SendWebhookJob.perform_later('invoice.created', invoice)
      GeneratePdfAndNotifyJob.perform_later(invoice:, email: should_deliver_email?)
      Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
      Integrations::Aggregator::SalesOrders::CreateJob.perform_later(invoice:) if invoice.should_sync_sales_order?
      Invoices::Payments::CreateService.new(invoice).call
      Utils::SegmentTrack.invoice_created(invoice)

      invoice.credit_notes.each do |credit_note|
        track_credit_note_created(credit_note)
        SendWebhookJob.perform_later('credit_note.created', credit_note)
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
  end
end
