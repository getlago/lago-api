# frozen_string_literal: true

module V1
  class PaymentSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        invoice_ids: invoice_id,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        payment_status: model.payable_payment_status,
        type: model.payment_type,
        reference: model.reference,
        external_payment_id: model.provider_payment_id,
        created_at: model.created_at.iso8601
      }

      payload.merge!(payment_receipt) if include?(:payment_receipt)
      payload
    end

    private

    def payment_receipt
      {
        payment_receipt: model.payment_receipt ?
          ::V1::PaymentReceiptSerializer.new(model.payment_receipt).serialize :
          {}
      }
    end

    def invoice_id
      model.payable.is_a?(Invoice) ? [model.payable.id] : model.payable.invoice_ids
    end
  end
end
