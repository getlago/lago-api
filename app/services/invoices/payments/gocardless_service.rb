# frozen_string_literal: true

module Invoices
  module Payments
    class GocardlessService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(invoice = nil)
        @invoice = invoice

        super
      end

      def update_payment_status(provider_payment_id:, status:)
        payment = Payment.find_by(provider_payment_id:)
        return result.not_found_failure!(resource: "gocardless_payment") unless payment

        result.payment = payment
        result.invoice = payment.payable
        return result if payment.payable.payment_succeeded?

        payment.update!(status:)

        invoice_payment_status = payment.payment_provider&.determine_payment_status(status)
        update_invoice_payment_status(payment_status: invoice_payment_status)

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def update_invoice_payment_status(payment_status:, deliver_webhook: true)
        update_invoice_result = Invoices::UpdateService.call(
          invoice: result.invoice,
          params: {
            payment_status:,
            ready_for_payment_processing: payment_status.to_sym != :succeeded
          },
          webhook_notification: deliver_webhook
        )
        update_invoice_result.raise_if_error!
      end
    end
  end
end
