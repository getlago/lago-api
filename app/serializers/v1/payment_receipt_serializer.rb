# frozen_string_literal: true

module V1
  class PaymentReceiptSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        number: model.reload.number,
        payment: payment,
        created_at: model.created_at.iso8601
      }
    end

    private

    def payment
      ::V1::PaymentSerializer.new(model.payment).serialize
    end
  end
end
