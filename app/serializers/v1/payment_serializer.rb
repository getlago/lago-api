# frozen_string_literal: true

module V1
  class PaymentSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        invoice_id: invoice_id,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        payment_status: model.payable_payment_status,
        type: model.payment_type,
        reference: model.reference,
        payment_provider_id: model.payment_provider_id,
        payment_provider_customer_id: model.payment_provider_customer_id,
        external_payment_id: model.provider_payment_id,
        created_at: model.created_at.iso8601
      }
    end

    private

    def invoice_id
      model.payable.is_a?(Invoice) ? model.payable.id : model.payable.invoice_ids
    end
  end
end
