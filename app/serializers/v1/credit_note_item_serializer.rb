# frozen_string_literal: true

module V1
  class CreditNoteItemSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        credit_amount_cents: model.credit_amount_cents,
        credit_amount_currency: model.credit_amount_currency,
        refund_amount_cents: model.refund_amount_cents,
        refund_amount_currency: model.refund_amount_currency,
        fee: fee,
      }
    end

    private

    def fee
      ::V1::FeeSerializer.new(
        model.fee,
      ).serialize
    end
  end
end
