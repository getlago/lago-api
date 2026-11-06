# frozen_string_literal: true

module V1
  class PaymentSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        lago_customer_id: customer&.id, # TODO: why?
        external_customer_id: customer&.external_id,
        invoice_ids: invoice_ids,
        invoice_numbers: model.invoice_numbers,
        lago_payable_id: model.payable_id,
        payable_type: model.payable_type,

        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        status: model.status, # TODO: Should be `provider_status`
        payment_status: model.payable_payment_status,
        type: model.payment_type,
        reference: model.reference,

        payment_provider_code: model.payment_provider&.code,
        payment_provider_type: model.payment_provider&.type,
        external_payment_id: model.provider_payment_id, # DEPRECATED, use provider_payment_id
        provider_payment_id: model.provider_payment_id,
        provider_customer_id: model.payment_provider_customer&.provider_customer_id, # TODO: remove option?
        next_action: model.provider_payment_data,

        created_at: model.created_at.iso8601
      }

      payload.merge!(payment_receipt) if include?(:payment_receipt)
      payload.merge!(payment_method) if include?(:payment_method) && model.payment_method
      payload[:x402_settlement] = x402_settlement if model.payment_type_x402?
      payload
    end

    private

    def payment_method
      {
        payment_method: ::V1::PaymentMethodSerializer.new(model.payment_method).serialize
      }
    end

    def payment_receipt
      {
        payment_receipt: model.payment_receipt ?
          ::V1::PaymentReceiptSerializer.new(model.payment_receipt).serialize :
          {}
      }
    end

    def x402_settlement
      settlement = model.x402_settlement

      if settlement
        {
          lago_id: settlement.id,
          network: settlement.network,
          transaction_hash: settlement.transaction_hash,
          payer_address: settlement.payer_address
        }
      end
    end

    # The payable can be missing when the invoice or payment request row it points to
    # no longer exists. Fall back to the payment's own customer in that case.
    def customer
      @customer ||= model.payable&.customer || model.customer
    end

    def invoice_ids
      payable = model.payable
      return [] if payable.nil?

      payable.is_a?(Invoice) ? [payable.id] : payable.invoice_ids
    end
  end
end
