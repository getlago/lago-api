# frozen_string_literal: true

module V2
  class RatePhaseSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        code: model.code,
        position: model.position,
        name: model.name,
        billing_interval_cycle_count: model.billing_interval_cycle_count,
        rate_override: rate_override
      }
    end

    private

    def rate_override
      return unless model.rate_override

      ::V2::RateOverrideSerializer.new(model.rate_override).serialize
    end
  end
end
