# frozen_string_literal: true

module V2
  class RateCardRateSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        code: model.code,
        effective_from: format_time(model.effective_from),
        status: model.status,
        rate_model: model.rate_model,
        rate_properties: ::RateProperties.present(model.rate_properties),
        min_amount_cents: model.min_amount_cents,
        billing_interval_count: model.billing_interval_count,
        billing_interval_unit: model.billing_interval_unit,
        applied_pricing_unit_conversion_rate: model.applied_pricing_unit_conversion_rate,
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at),
        **deleted_at_payload
      }
    end
  end
end
