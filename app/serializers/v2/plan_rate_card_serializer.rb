# frozen_string_literal: true

module V2
  class PlanRateCardSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        plan_code: model.catalog_plan.code,
        rate_card_code: model.rate_card.code,
        units: model.units,
        **(include?(:rate_phases) ? {rate_phases: rate_phases} : {}),
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at),
        deleted_at: format_time(model.deleted_at)
      }
    end

    private

    def rate_phases
      model.rate_phases.order(:position).map do |phase|
        ::V2::RatePhaseSerializer.new(phase).serialize
      end
    end
  end
end
