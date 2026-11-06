# frozen_string_literal: true

module V2
  class RateCardRateSerializer < ModelSerializer
    timestamps :effective_from, :created_at, :updated_at, :deleted_at

    def serialize
      {
        lago_id: model.id,
        code: model.code,
        rate_card_code: model.rate_card&.code,
        status: model.status,
        rate_model: model.rate_model,
        rate_properties: ::RateProperties.present(model.rate_properties),
        min_amount_cents: model.min_amount_cents,
        billing_interval_count: model.billing_interval_count,
        billing_interval_unit: model.billing_interval_unit,
        applied_pricing_unit_conversion_rate: model.applied_pricing_unit_conversion_rate
      }
    end
  end
end
