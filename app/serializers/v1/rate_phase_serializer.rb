# frozen_string_literal: true

module V1
  class RatePhaseSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        position: model.position,
        name: model.name,
        billing_interval_cycle_count: model.billing_interval_cycle_count,
        rate_override: nil
      }
    end
  end
end
