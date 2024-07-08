# frozen_string_literal: true

module V1
  class InvoiceSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        sequential_id: model.sequential_id,
        number: model.number,
        issuing_date: model.issuing_date&.iso8601,
        payment_due_date: model.payment_due_date&.iso8601,
        net_payment_term: model.net_payment_term,
        invoice_type: model.invoice_type,
        status: model.status,
        payment_status: model.payment_status,
        payment_dispute_lost_at: model.payment_dispute_lost_at,
        payment_overdue: model.payment_overdue,
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
        version_number: model.version_number
      }

      payload.merge!(customer) if include?(:customer)
      payload.merge!(subscriptions) if include?(:subscriptions)
      payload.merge!(fees) if include?(:fees)
      payload.merge!(credits) if include?(:credits)
      payload.merge!(metadata) if include?(:metadata)
      payload.merge!(applied_taxes) if include?(:applied_taxes)

      payload
    end

    private

    def customer
      {
        customer: ::V1::CustomerSerializer.new(model.customer).serialize
      }
    end

    def subscriptions
      ::CollectionSerializer.new(
        model.subscriptions.includes([:customer, :plan]), ::V1::SubscriptionSerializer, collection_name: 'subscriptions'
      ).serialize
    end

    def fees
      ::CollectionSerializer.new(
        model.fees.includes(
          [
            :true_up_fee,
            :subscription,
            :customer,
            :charge,
            :group,
            :billable_metric,
            {charge_filter: {values: :billable_metric_filter}}
          ]
        ),
        ::V1::FeeSerializer,
        collection_name: 'fees'
      ).serialize
    end

    def credits
      ::CollectionSerializer.new(model.credits, ::V1::CreditSerializer, collection_name: 'credits').serialize
    end

    def metadata
      ::CollectionSerializer.new(
        model.metadata,
        ::V1::Invoices::MetadataSerializer,
        collection_name: 'metadata'
      ).serialize
    end

    def applied_taxes
      ::CollectionSerializer.new(
        model.applied_taxes,
        ::V1::Invoices::AppliedTaxSerializer,
        collection_name: 'applied_taxes'
      ).serialize
    end
  end
end
