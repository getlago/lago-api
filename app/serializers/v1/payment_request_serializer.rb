# frozen_string_literal: true

module V1
  class PaymentRequestSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        email: model.email,
        created_at: model.created_at.iso8601,
        lago_invoice_ids:
      }

      payload.merge!(customer) if include?(:customer)

      payload
    end

    private

    def customer
      {
        customer: ::V1::CustomerSerializer.new(model.customer).serialize
      }
    end

    def lago_invoice_ids
      return model.payment_requestable if model.payment_requestable.is_a?(Invoice)

      model.payment_requestable.invoices.pluck(:id)
    end
  end
end
