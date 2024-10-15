# frozen_string_literal: true

module V1
  module Payments
    class RequiresActionSerializer < ModelSerializer
      def serialize
        {
          lago_payable_id: model.payable.id,
          lago_customer_id: model.payable.customer.id,
          status: model.status,
          external_customer_id: model.payable.customer.external_id,
          provider_customer_id: options[:provider_customer_id],
          payment_provider_code: model.payment_provider.code,
          payment_provider_type: model.payment_provider.type,
          provider_payment_id: model.provider_payment_id,
          next_action: model.provider_payment_data
        }
      end
    end
  end
end
