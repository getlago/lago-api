# frozen_string_literal: true

module V1
  module PaymentProviders
    class InvoicePaymentErrorSerializer < ModelSerializer
      alias invoice model

      def serialize
        {
          lago_invoice_id: invoice.id,
          lago_customer_id: invoice.customer.id,
          external_customer_id: invoice.customer.external_id,
          provider_customer_id: options[:provider_customer_id],
          payment_provider: invoice.customer.payment_provider,
          provider_error: options[:provider_error],
        }
      end
    end
  end
end
