# frozen_string_literal: true

module V1
  class InvoiceSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        sequential_id: model.sequential_id,
        from_date: model.from_date,
        to_date: model.to_date,
        issuing_date: model.issuing_date,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        vat_amount_cents: model.vat_amount_cents,
        vat_amount_currency: model.vat_amount_currency,
        total_amount_cents: model.total_amount_cents,
        total_amount_currency: model.total_amount_currency,
      }

      payload = payload.merge(customer) if include?(:customer)
      payload = payload.merge(subscription) if include?(:subscription)
      payload = payload.merge(fees) if include?(:fees)

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
  end
end
