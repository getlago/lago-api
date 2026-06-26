# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module V1
  class CreditNoteItemSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        amount_cents: model.amount_cents,
        precise_amount_cents: model.precise_amount_cents&.to_s,
        amount_currency: model.amount_currency,
        fee:
      }
    end

    private

    def fee
      ::V1::FeeSerializer.new(
        model.fee
      ).serialize
    end
  end
end
