# frozen_string_literal: true

module V2
  class PlanRateCardSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        plan_code: model.catalog_plan.code,
        rate_card_code: model.rate_card.code,
        units: model.units,
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at),
        **deleted_at_payload
      }
    end
  end
end
