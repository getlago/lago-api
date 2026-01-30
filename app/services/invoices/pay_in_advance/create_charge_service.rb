# frozen_string_literal: true

module Invoices
  module PayInAdvance
    class CreateChargeService < Invoices::PayInAdvance::BaseService
      Result = BaseResult[:invoice, :fees_taxes, :invoice_id]

      def initialize(charge:, event:, timestamp:)
        @charge = charge
        @event = Events::CommonFactory.new_instance(source: event)
        @timestamp = timestamp

        super
      end

      def call
        handle_record_errors do
          fee_result = generate_fees
          fees = fee_result.fees
          return result if fees.none?

          ApplicationRecord.transaction do
            ApplicationRecord.with_advisory_lock!(customer_lock_key, timeout_seconds: ACQUIRE_LOCK_TIMEOUT, transaction: true) do
              create_generating_invoice
              fees.each { |f| f.update!(invoice:) }

              finalize_invoice

              if tax_error?(fee_result)
                invoice.failed!
                invoice.fees.each { |f| SendWebhookJob.perform_later("fee.created", f) }
                create_error_detail(fee_result.error.messages.dig(:tax_error)&.first)
                Utils::ActivityLog.produce(invoice, "invoice.failed")
                next
              end

              Invoices::ComputeAmountsFromFees.call(invoice:, provider_taxes: result.fees_taxes)
              apply_credits_and_finalize
            end
          end
          return fee_result if tax_error?(fee_result)

          result.invoice = invoice
          trigger_post_creation_jobs

          result
        end
      end

      private

      attr_accessor :timestamp, :charge, :event

      delegate :subscription, to: :event
      delegate :customer, to: :subscription

      def create_generating_invoice
        invoice_result = Invoices::CreateGeneratingService.call(
          customer:,
          invoice_type: :subscription,
          currency: customer.currency,
          datetime: Time.zone.at(timestamp),
          charge_in_advance: true,
          invoice_id: result.invoice_id
        ) do |invoice|
          Invoices::CreateInvoiceSubscriptionService
            .call(invoice:, subscriptions: [subscription], timestamp:, invoicing_reason: :in_advance_charge)
            .raise_if_error!
        end
        invoice_result.raise_if_error!
        @invoice = invoice_result.invoice
      end

      def generate_fees
        fee_result = Fees::CreatePayInAdvanceService.call(charge:, event:, estimate: true)
        fee_result.raise_if_error! unless tax_error?(fee_result)

        result.fees_taxes = fee_result.fees_taxes
        result.invoice_id = fee_result.invoice_id

        fee_result
      end

      def tax_error?(result)
        return false unless result.error.is_a?(BaseService::ValidationFailure)

        result.error&.messages&.dig(:tax_error).present?
      end

      def create_error_detail(code)
        error_result = ErrorDetails::CreateService.call(
          owner: invoice,
          organization: invoice.organization,
          params: {
            error_code: :tax_error,
            details: {
              tax_error: code
            }
          }
        )
        error_result.raise_if_error!
      end
    end
  end
end
