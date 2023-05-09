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
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        vat_amount_cents: model.vat_amount_cents,
        vat_amount_currency: model.vat_amount_currency,
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
      }

      payload = payload.merge(date_boundaries) if model.charge? || model.subscription?
      payload.merge!(instant_charge_attributes) if model.instant_charge?

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

    def instant_charge_attributes
      return {} unless model.instant_charge?

      event = model.subscription.organization.events.find_by(id: model.instant_event_id)

      {
        lago_subscription_id: model.subscription_id,
        external_subscription_id: model.subscription&.external_id,
        lago_customer_id: model.customer.id,
        external_customer_id: model.customer.external_id,
        event_transaction_id: event&.transaction_id,
      }
    end
  end
end
