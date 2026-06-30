# frozen_string_literal: true

module V1
  class PlanRateCardSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        plan_code: model.plan.code,
        rate_card_code: model.rate_card.code,
        units: model.units,
        rate_phases_count: model.rate_phases.count,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end
  end
end
