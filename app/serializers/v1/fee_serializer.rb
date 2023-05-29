# frozen_string_literal: true

module V1
  class FeeSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        lago_group_id: model.group_id,
        lago_invoice_id: model.invoice_id,
        lago_true_up_fee_id: model.true_up_fee&.id,
        lago_true_up_parent_fee_id: model.true_up_parent_fee_id,
        item: {
          type: model.fee_type,
          code: model.item_code,
          name: model.item_name,
          lago_item_id: model.item_id,
          item_type: model.item_type,
        },
        pay_in_advance: model.pay_in_advance,
        invoiceable: model.charge&.invoiceable || false,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        taxes_amount_cents: model.taxes_amount_cents,
        taxes_rate: model.taxes_rate,
        total_amount_cents: model.total_amount_cents,
        total_amount_currency: model.amount_currency,
        units: model.units,
        description: model.description,
        unit_amount_cents: model.unit_amount_cents,
        events_count: model.events_count,
        payment_status: model.payment_status,
        created_at: model.created_at&.iso8601,
        succeeded_at: model.succeeded_at&.iso8601,
        failed_at: model.failed_at&.iso8601,
        refunded_at: model.refunded_at&.iso8601,
      }.merge(legacy_values)

      payload.merge!(date_boundaries) if model.charge? || model.subscription?
      payload.merge!(pay_in_advance_charge_attributes) if model.pay_in_advance?
      payload.merge!(taxes) if include?(:taxes)

      payload
    end

    private

    def date_boundaries
      {
        from_date:,
        to_date:,
      }
    end

    def from_date
      model.properties['from_datetime']&.to_datetime&.iso8601
    end

    def to_date
      model.properties['to_datetime']&.to_datetime&.iso8601
    end

    def pay_in_advance_charge_attributes
      return {} unless model.pay_in_advance?

      event = model.subscription.organization.events.find_by(id: model.pay_in_advance_event_id)

      {
        lago_subscription_id: model.subscription_id,
        external_subscription_id: model.subscription&.external_id,
        lago_customer_id: model.customer.id,
        external_customer_id: model.customer.external_id,
        event_transaction_id: event&.transaction_id,
      }
    end

    def taxes
      ::CollectionSerializer.new(model.taxes, ::V1::TaxSerializer, collection_name: 'taxes').serialize
    end

    def legacy_values
      ::V1::Legacy::FeeSerializer.new(model).serialize
    end
  end
end
