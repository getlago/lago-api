# frozen_string_literal: true

module V1
  class PlanProductItemSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_plan_id: model.plan_id,
        lago_rate_card_id: model.rate_card_id,
        rate_card_code: model.rate_card.code,
        units: model.units,
        rate_phases_count: model.rate_phases.count,
        created_at: model.created_at.iso8601
      }
    end
  end
end
