# frozen_string_literal: true

module Invoices
  class RetryService < BaseService
    def initialize(invoice:)
      @invoice = invoice

      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') unless invoice
      #return result.not_allowed_failure!(code: 'invalid_status') unless invoice.failed?

      taxes_result = Integrations::Aggregator::Taxes::Invoices::CreateService.call(invoice:, fees: invoice.fees)

      unless taxes_result.success?
        return result.service_failure!(code: 'taxes', message: 'fetching failed')
      end

      @taxes_fees = taxes_result.fees

      ActiveRecord::Base.transaction do
        invoice.status = :finalized

        # TODO: pass provider taxes
        Invoices::ComputeAmountsFromFees.call(invoice:)

        create_credit_note_credit if should_create_credit_note_credit?
        create_applied_prepaid_credit if should_create_applied_prepaid_credit?

        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        invoice.save!

        invoice.reload

        result.invoice = invoice
      end

      SendWebhookJob.perform_later('invoice.created', invoice) if invoice.organization.webhook_endpoints.any?
      GeneratePdfAndNotifyJob.perform_later(invoice:, email: should_deliver_email?)
      Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
      Integrations::Aggregator::SalesOrders::CreateJob.perform_later(invoice:) if invoice.should_sync_sales_order?
      Invoices::Payments::CreateService.new(invoice).call
      Utils::SegmentTrack.invoice_created(invoice)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    rescue => e
      result.fail_with_error!(e)
    end

    private

    attr_accessor :invoice, :taxes_fees

    def should_deliver_email?
      License.premium? &&
        invoice.organization.email_settings.include?('invoice.finalized')
    end

    def wallet
      return @wallet if @wallet

      @wallet = customer.wallets.active.first
    end

    def credit_notes
      @credit_notes ||= customer.credit_notes
        .finalized
        .available
        .where.not(invoice_id: invoice.id)
        .order(created_at: :asc)
    end

    def should_create_credit_note_credit?
      credit_notes.any?
    end

    def should_create_applied_prepaid_credit?
      return false unless wallet&.active?
      return false unless invoice.total_amount_cents&.positive?

      wallet.balance.positive?
    end

    def create_credit_note_credit
      credit_result = Credits::CreditNoteService.new(invoice:, credit_notes:).call
      credit_result.raise_if_error!

      invoice.total_amount_cents -= credit_result.credits.sum(&:amount_cents) if credit_result.credits
    end

    def create_applied_prepaid_credit
      prepaid_credit_result = Credits::AppliedPrepaidCreditService.call(invoice:, wallet:)
      prepaid_credit_result.raise_if_error!

      invoice.total_amount_cents -= prepaid_credit_result.prepaid_credit_amount_cents
    end
  end
end
