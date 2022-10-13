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
        credit_status: model.credit_status,
        reason: model.reason,
        total_amount_cents: model.total_amount_cents,
        total_amount_currency: model.total_amount_currency,
        balance_amount_cents: model.balance_amount_cents,
        balance_amount_currency: model.balance_amount_currency,
        credit_amount_cents: model.credit_amount_cents,
        credit_amount_currency: model.credit_amount_currency,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        file_url: model.file_url,
      }

      payload = payload.merge(customer) if include?(:customer)
      payload = payload.merge(items) if include?(:items)

      payload
    end

    private

    def customer
      {
        customer: ::V1::CustomerSerializer.new(model.customer).serialize,
      }
    end

    def items
      ::CollectionSerializer.new(
        model.items.order(created_at: :asc),
        ::V1::CreditNoteItemSerializer,
        collection_name: 'items',
      ).serialize
    end
  end
end
