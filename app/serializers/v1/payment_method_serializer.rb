# frozen_string_literal: true

module V1
  class PaymentMethodSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        is_default: model.is_default,
        payment_provider_code: model.payment_provider&.code,
        payment_provider_type: model.payment_provider_type,
        created_at: model.created_at.iso8601
      }

      payload.merge!(customer) if include?(:customer)

      payload
    end

    private

    def customer
      {
        customer: ::V1::CustomerSerializer.new(model.customer).serialize
      }
    end
  end
end
