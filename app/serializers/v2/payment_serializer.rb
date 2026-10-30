# frozen_string_literal: true

module V2
  class PaymentSerializer < ModelSerializer
    PRELOADS = [:customer, :payment_provider, :payment_provider_customer, {payable: :applied_invoices}].freeze

    def serialize
      {
        lago_id: model.id,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        lago_payable_id: model.payable_id,
        payable_type: model.payable_type,
        lago_invoice_ids: invoice_ids,
        amount_cents: model.amount_cents,
        currency: model.amount_currency,
        status: model.status,
        payment_status: model.payable_payment_status,
        payment_type: model.payment_type,
        reference: model.reference,
        payment_provider_code: model.payment_provider&.code,
        payment_provider_type: model.payment_provider&.payment_type,
        provider_payment_id: model.provider_payment_id,
        provider_customer_id: model.payment_provider_customer&.provider_customer_id,
        next_action: model.provider_payment_data,
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at)
      }
    end

    private

    def invoice_ids
      case model.payable
      when Invoice then [model.payable_id]
      when PaymentRequest then model.payable.applied_invoices.map(&:invoice_id)
      else []
      end
    end
  end
end
