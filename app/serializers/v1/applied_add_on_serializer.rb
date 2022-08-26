# frozen_string_literal: true

module V1
  class AppliedAddOnSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_add_on_id: model.add_on.id,
        add_on_code: model.add_on.code,
        lago_customer_id: model.customer.id,
        external_customer_id: model.customer.external_id,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        created_at: model.created_at.iso8601,
      }
    end
  end
end
