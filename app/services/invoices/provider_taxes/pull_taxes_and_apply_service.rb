# frozen_string_literal: true

module Invoices
  module ProviderTaxes
    class PullTaxesAndApplyService < BaseService
      def initialize(invoice:)
        @invoice = invoice

        super
      end

      def call
        return result.not_found_failure!(resource: 'invoice') unless invoice
        return result.not_found_failure!(resource: 'integration_customer') unless customer.anrok_customer
        return result.not_allowed_failure!(code: 'invalid_status') unless invoice.pending? || invoice.draft?
        return result.not_allowed_failure!(code: 'invalid_tax_status') unless invoice.tax_pending?

        invoice.error_details.tax_error.discard_all
        taxes_result = if invoice.draft?
          Integrations::Aggregator::Taxes::Invoices::CreateDraftService.call(invoice:, fees: invoice.fees)
        else
          Integrations::Aggregator::Taxes::Invoices::CreateService.call(invoice:, fees: invoice.fees)
        end

        unless taxes_result.success?
          create_error_detail(taxes_result.error)
          invoice.tax_status = 'failed'
          invoice.status = 'failed' unless invoice.draft?
          invoice.save!

          return result.validation_failure!(errors: {tax_error: [taxes_result.error.code]})
        end

        provider_taxes = taxes_result.fees

        ActiveRecord::Base.transaction do
          Invoices::ComputeAmountsFromFees.call(invoice:, provider_taxes:)

          create_credit_note_credit if should_create_credit_note_credit?
          create_applied_prepaid_credit if should_create_applied_prepaid_credit?

          invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
          invoice.tax_status = 'succeeded'
          if invoice.draft?
            invoice.status = :draft
          else
            Invoices::TransitionToFinalStatusService.call(invoice:)
          end

          invoice.save!
          invoice.reload

          result.invoice = invoice
        end

        if invoice.finalized?
          SendWebhookJob.perform_later('invoice.created', invoice)
          GeneratePdfAndNotifyJob.perform_later(invoice:, email: should_deliver_email?)
          Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
          Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?
          Invoices::Payments::CreateService.call_async(invoice:)
          Utils::SegmentTrack.invoice_created(invoice)
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        e.result
      rescue => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :invoice

      def should_deliver_email?
        License.premium? &&
          invoice.organization.email_settings.include?('invoice.finalized')
      end

      def wallet
        return @wallet if @wallet

        @wallet = customer.wallets.active.first
      end

      def should_create_credit_note_credit?
        return false if invoice.draft?

        !invoice.one_off?
      end

      def should_create_applied_prepaid_credit?
        return false if invoice.draft?
        return false if invoice.one_off?
        return false unless wallet&.active?
        return false unless invoice.total_amount_cents&.positive?

        wallet.balance.positive?
      end

      def create_credit_note_credit
        credit_result = Credits::CreditNoteService.new(invoice:).call
        credit_result.raise_if_error!

        invoice.total_amount_cents -= credit_result.credits.sum(&:amount_cents) if credit_result.credits
      end

      def create_applied_prepaid_credit
        prepaid_credit_result = Credits::AppliedPrepaidCreditService.call(invoice:, wallet:)
        prepaid_credit_result.raise_if_error!

        invoice.total_amount_cents -= prepaid_credit_result.prepaid_credit_amount_cents
      end

      def customer
        @customer ||= invoice.customer
      end

      def create_error_detail(error)
        error_result = ErrorDetails::CreateService.call(
          owner: invoice,
          organization: invoice.organization,
          params: {
            error_code: :tax_error,
            details: {
              tax_error: error.code
            }.tap do |details|
              details[:tax_error_message] = error.error_message if error.code == 'validationError'
            end
          }
        )
        error_result.raise_if_error!
      end
    end
  end
end
