# frozen_string_literal: true
#
module V1
  class ChargeSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_billable_metric_id: model.billable_metric_id,
        created_at: model.created_at.iso8601,
        amount_currency: model.amount_currency,
        charge_model: model.charge_model,
        properties: model.properties,
      }
    end
  end
end
