# frozen_string_literal: true

module V1
  class ChargeUsageSerializer < ModelSerializer
    def serialize
      {
        units: model.units,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        charge_id: model.charge.id,
        charge_model: model.charge.charge_model,
        billable_metric_id: model.billable_metric.id,
        billable_metric_name: model.billable_metric.name,
        billable_metric_code: model.billable_metric.code,
        billable_metric_aggregation_type: model.billable_metric.aggregation_type,
      }
    end
  end
end
