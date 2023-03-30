# frozen_string_literal: true

module V1
  class FeeSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        lago_group_id: model.group_id,
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
        events_count: model.events_count,
        lago_invoice_id: model.invoice_id,
        external_subscription_id: model.subscription&.external_id,
        payment_status: model.payment_status,
        created_at: model.created_at&.iso8601,
        succeeded_at: model.succeeded_at&.iso8601,
        failed_at: model.failed_at&.iso8601,
        refunded_at: model.refunded_at&.iso8601,
      }

      payload = payload.merge(date_boundaries) if model.charge? || model.subscription?

      payload
    end

    private

    def date_boundaries
      {
        date_from:,
        date_to:,
      }
    end

    def date_from
      invoice = model.invoice
      subscription = model.subscription

      invoice.invoice_subscription(subscription.id).from_datetime_in_customer_timezone&.to_date
    end

    def date_to
      invoice = model.invoice
      subscription = model.subscription

      invoice.invoice_subscription(subscription.id).to_datetime_in_customer_timezone&.to_date
    end
  end
end
