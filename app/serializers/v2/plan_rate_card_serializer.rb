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
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        deleted_at: model.deleted_at&.iso8601
      }
    end

    private

    def rate_phases
      model.rate_phases.order(:position).map do |phase|
        ::V2::RatePhaseSerializer.new(phase, nested_options).serialize
      end
    end
  end
end
