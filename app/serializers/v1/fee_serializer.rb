# frozen_string_literal: true

module V1
  class FeeSerializer < ModelSerializer
    def serialize
      {
        item: {
          type: model.item_type,
          code: model.item_code,
          name: model.item_name,
        },
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        vat_amount_cents: model.vat_amount_cents,
        vat_amount_currency: model.vat_amount_currency,
        units: model.units,
      }
    end
  end
end
