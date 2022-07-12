# frozen_string_literal: true

module V1
  class InvoiceSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        sequential_id: model.sequential_id,
        number: model.number,
        from_date: model.from_date.iso8601,
        to_date: model.to_date.iso8601,
        charges_from_date: model.to_date.iso8601,
        issuing_date: model.issuing_date.iso8601,
        invoice_type: model.invoice_type,
        status: model.status,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        vat_amount_cents: model.vat_amount_cents,
        vat_amount_currency: model.vat_amount_currency,
        total_amount_cents: model.total_amount_cents,
        total_amount_currency: model.total_amount_currency,
        file_url: model.file_url,
      }

      payload = payload.merge(customer) if include?(:customer)
      payload = payload.merge(subscription) if include?(:subscription)
      payload = payload.merge(fees) if include?(:fees)
      payload = payload.merge(credits) if include?(:credits)

      payload
    end

    private

    def customer
      {
        customer: ::V1::CustomerSerializer.new(model.customer).serialize,
      }
    end

    def subscription
      {
        subscription: ::V1::SubscriptionSerializer.new(model.subscription).serialize,
      }
    end

    def fees
      ::CollectionSerializer.new(model.fees, ::V1::FeeSerializer, collection_name: 'fees').serialize
    end

    def credits
      ::CollectionSerializer.new(model.credits, ::V1::CreditSerializer, collection_name: 'credit').serialize
    end
  end
end
