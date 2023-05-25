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
        currency: model.currency,
        fees_amount_cents: model.fees_amount_cents,
        taxes_amount_cents: model.taxes_amount_cents,
        coupons_amount_cents: model.coupons_amount_cents,
        credit_notes_amount_cents: model.credit_notes_amount_cents,
        sub_total_excluding_taxes_amount_cents: model.sub_total_excluding_taxes_amount_cents,
        sub_total_including_taxes_amount_cents: model.sub_total_including_taxes_amount_cents,
        total_amount_cents: model.total_amount_cents,
        prepaid_credit_amount_cents: model.prepaid_credit_amount_cents,
        file_url: model.file_url,
        version_number: model.version_number,
      }.merge(legacy_values)

      payload.merge!(customer) if include?(:customer)
      payload.merge!(subscriptions) if include?(:subscriptions)
      payload.merge!(fees) if include?(:fees)
      payload.merge!(credits) if include?(:credits)
      payload.merge!(metadata) if include?(:metadata)
      payload.merge!(taxes) if include?(:taxes)

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

    def taxes
      ::CollectionSerializer.new(model.taxes, ::V1::TaxSerializer, collection_name: 'taxes').serialize
    end

    def legacy_values
      ::V1::Legacy::InvoiceSerializer.new(model).serialize
    end
  end
end
