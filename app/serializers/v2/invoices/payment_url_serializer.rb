# frozen_string_literal: true

module V2
  module Invoices
    class PaymentUrlSerializer < ModelSerializer
      def serialize
        {
          lago_customer_id: model.customer_id,
          external_customer_id: model.customer.external_id,
          payment_provider: model.customer.payment_provider,
          lago_invoice_id: model.id,
          payment_url: options[:payment_url]
        }
      end
    end
  end
end
