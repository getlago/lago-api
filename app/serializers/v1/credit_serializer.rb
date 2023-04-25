# frozen_string_literal: true

module V1
  class CreditSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        before_vat: model.before_vat,
        item: {
          lago_id: model.item_id,
          type: model.item_type,
          code: model.item_code,
          name: model.item_name,
        },
        invoice: {
          lago_id: model.invoice_id,
          payment_status: model.invoice.payment_status,
        },
      }
    end
  end
end
