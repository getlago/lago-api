# frozen_string_literal: true

module V2
  class PaymentRequestSerializer < ModelSerializer
    PRELOADS = %i[customer applied_invoices].freeze

    def serialize
      {
        lago_id: model.id,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        email: model.email,
        amount_cents: model.amount_cents,
        currency: model.amount_currency,
        payment_status: model.payment_status,
        lago_invoice_ids: model.applied_invoices.map(&:invoice_id),
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at)
      }
    end
  end
end
