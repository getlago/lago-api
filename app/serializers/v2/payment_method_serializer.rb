# frozen_string_literal: true

module V2
  class PaymentMethodSerializer < ModelSerializer
    PRELOADS = %i[customer payment_provider].freeze

    def serialize
      {
        lago_id: model.id,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        is_default: model.is_default,
        payment_provider_code: model.payment_provider&.code,
        payment_provider_name: model.payment_provider&.name,
        payment_provider_type: model.payment_provider_type,
        provider_method_id: model.provider_method_id,
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at),
        deleted_at: format_time(model.deleted_at)
      }
    end
  end
end
