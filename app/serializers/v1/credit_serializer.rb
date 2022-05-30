# frozen_string_literal: true

module V1
  class CreditSerializer < ModelSerializer
    def serialize
      {
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        item: {
          type: model.item_type,
          code: model.item_code,
          name: model.item_name,
        },
      }
    end
  end
end
