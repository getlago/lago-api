# frozen_string_literal: true

module V1
  class RateOverrideSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        rate_model: model.rate_model,
        rate_properties: model.rate_properties,
        min_amount_cents: model.min_amount_cents,
        billing_interval_count: model.billing_interval_count,
        billing_interval_unit: model.billing_interval_unit,
        pricing_unit_conversion_rate: model.pricing_unit_conversion_rate
      }
    end
  end
end
