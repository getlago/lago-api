# frozen_string_literal: true

module V1
  class FeeSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_group_id: model.group&.id,
        item: {
          type: model.fee_type,
          code: model.item_code,
          name: model.item_name,
        },
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        vat_amount_cents: model.vat_amount_cents,
        vat_amount_currency: model.vat_amount_currency,
        units: model.units,
        events_count: model.events_count,
      }
    end
  end
end
