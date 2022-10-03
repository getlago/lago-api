# frozen_string_literal: true

module V1
  class CreditNoteItemSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_fee_id: fee.id,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        fee_amount_cents: fee.amount_cents,
        fee_amount_currency: fee.amount_currency,
        fee_item: {
          type: fee.fee_type,
          code: fee.item_code,
          name: fee.item_name,
        },
      }
    end

    delegate :fee, to: :model
  end
end
