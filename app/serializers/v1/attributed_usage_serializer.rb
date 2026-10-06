# frozen_string_literal: true

module V1
  class AttributedUsageSerializer < ModelSerializer
    def serialize
      {
        lago_subscription_id: model.subscription.id,
        external_subscription_id: model.subscription.external_id,
        group_by: model.group_by,
        basis: model.basis,
        from_datetime: model.from_datetime.iso8601,
        to_datetime: model.to_datetime.iso8601,
        currency: model.currency,
        rows: model.rows.map { serialize_row(it) },
        unattributed: serialize_aggregate(model.unattributed),
        totals: serialize_aggregate(model.totals)
      }
    end

    private

    def serialize_row(row)
      {
        value: row.value,
        rank: row.rank,
        **serialize_aggregate(row)
      }
    end

    def serialize_aggregate(aggregate)
      {
        **amounts(aggregate.amount_cents),
        events_count: aggregate.events_count,
        charges_usage: aggregate.cells.map { serialize_cell(it) }
      }
    end

    def serialize_cell(cell)
      {
        lago_charge_id: cell.charge.id,
        charge_code: cell.charge.code,
        billable_metric_code: cell.charge.billable_metric.code,
        lago_charge_filter_id: cell.charge_filter&.id,
        charge_filter_values: cell.charge_filter&.to_h,
        charge_filter_invoice_display_name: cell.charge_filter&.invoice_display_name,
        units: cell.units.to_s,
        **amounts(cell.amount_cents),
        events_count: cell.events_count
      }
    end

    def amounts(amount_cents)
      {
        amount_cents: amount_cents&.round,
        precise_amount_cents: amount_cents&.to_s
      }
    end
  end
end
