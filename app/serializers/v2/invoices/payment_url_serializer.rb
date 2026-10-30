# frozen_string_literal: true

module V2
  module Invoices
    class PaymentUrlSerializer < ModelSerializer
      PaymentUrl = Data.define(:invoice, :url)

      def serialize
        invoice = model.invoice

        {
          lago_customer_id: invoice.customer_id,
          external_customer_id: invoice.customer.external_id,
          payment_provider: invoice.customer.payment_provider,
          lago_invoice_id: invoice.id,
          payment_url: model.url
        }
      end
    end
  end
end
