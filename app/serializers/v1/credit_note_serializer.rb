# frozen_string_literal: true

module V1
  class CreditNoteSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        sequential_id: model.sequential_id,
        number: model.number,
        lago_invoice_id: model.invoice_id,
        invoice_number: model.invoice.number,
        status: model.status,
        reason: model.reason,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        remaining_amount_cents: model.remaining_amount_cents,
        remaining_amount_currency: model.remaining_amount_currency,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        file_url: nil, # TODO: Expose credit note document in API
      }

      payload = payload.merge(fees) if include?(:fees)

      payload
    end

    private

    def fees
      ::CollectionSerializer.new(model.fees, ::V1::FeeSerializer, collection_name: 'fees').serialize
    end
  end
end
