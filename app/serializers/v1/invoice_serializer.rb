# frozen_string_literal: true

module V1
  class InvoiceSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        sequential_id: model.sequential_id,
        number: model.number,
        issuing_date: model.issuing_date.iso8601,
        invoice_type: model.invoice_type,
        status: model.status,
        payment_status: model.payment_status,
        fees_amount_cents: model.fees_amount_cents,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        vat_amount_cents: model.vat_amount_cents,
        vat_amount_currency: model.vat_amount_currency,
        coupons_amount_cents: model.coupons_amount_cents,
        credit_notes_amount_cents: model.credit_notes_amount_cents,
        credit_amount_cents: model.credit_amount_cents,
        credit_amount_currency: model.credit_amount_currency,
        total_amount_cents: model.total_amount_cents,
        total_amount_currency: model.total_amount_currency,
        prepaid_credit_amount_cents: model.prepaid_credit_amount_cents,
        file_url: model.file_url,
        legacy: model.legacy,
      }

      payload = payload.merge(customer) if include?(:customer)
      payload = payload.merge(subscriptions) if include?(:subscriptions)
      payload = payload.merge(fees) if include?(:fees)
      payload = payload.merge(credits) if include?(:credits)
      payload = payload.merge(metadata) if include?(:metadata)

      payload
    end

    private

    def customer
      {
        customer: ::V1::CustomerSerializer.new(model.customer).serialize,
      }
    end

    def subscriptions
      ::CollectionSerializer
        .new(model.subscriptions, ::V1::SubscriptionSerializer, collection_name: 'subscriptions').serialize
    end

    def fees
      ::CollectionSerializer.new(model.fees, ::V1::FeeSerializer, collection_name: 'fees').serialize
    end

    def credits
      ::CollectionSerializer.new(model.credits, ::V1::CreditSerializer, collection_name: 'credits').serialize
    end

    def metadata
      ::CollectionSerializer.new(
        model.metadata,
        ::V1::Invoices::MetadataSerializer,
        collection_name: 'metadata',
      ).serialize
    end
  end
end
