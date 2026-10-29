# frozen_string_literal: true

module V2
  module Customers
    class CheckoutUrlSerializer < ModelSerializer
      CheckoutUrl = Data.define(:customer, :url)

      def serialize
        customer = model.customer

        {
          lago_customer_id: customer.id,
          external_customer_id: customer.external_id,
          payment_provider: customer.payment_provider,
          payment_provider_code: customer.payment_provider_code,
          checkout_url: model.url
        }
      end
    end
  end
end
