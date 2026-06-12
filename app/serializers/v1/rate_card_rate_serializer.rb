# frozen_string_literal: true

module V1
  class RateCardRateSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        effective_datetime: model.effective_datetime.iso8601,
        status: model.status,
        rate_model: model.rate_model,
        rate_properties: model.rate_properties,
        min_amount_cents: model.min_amount_cents,
        billing_interval_count: model.billing_interval_count,
        billing_interval_unit: model.billing_interval_unit,
        applied_pricing_unit_conversion_rate: model.applied_pricing_unit_conversion_rate,
        created_at: model.created_at.iso8601
      }
    end
  end
end
