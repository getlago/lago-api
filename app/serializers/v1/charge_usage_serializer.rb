# frozen_string_literal: true

module V1
  class ChargeUsageSerializer < ModelSerializer
    def serialize
      {
        units: model.units,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        charge: {
          lago_id: model.charge.id,
          charge_model: model.charge.charge_model,
        },
        billable_metric: {
          lago_id: model.billable_metric.id,
          name: model.billable_metric.name,
          code: model.billable_metric.code,
          aggregation_type: model.billable_metric.aggregation_type,
        },
        groups: model.groups.map do |group|
          {
            lago_id: group.id,
            key: group.key,
            value: group.value,
            units: group.units,
            amount_cents: group.amount_cents,
          }
        end,
      }
    end
  end
end
