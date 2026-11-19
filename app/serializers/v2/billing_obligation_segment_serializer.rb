# frozen_string_literal: true

module V2
  class BillingObligationSegmentSerializer < ModelSerializer
    timestamps :period_from, :period_to

    def serialize
      override = obligation.cycle.phase.rate_override
      {
        proration_ratio: obligation.proration_ratio_for(model),
        lago_rate_id: model.rate.id,
        rate_code: model.rate.code,
        lago_rate_override_id: override&.id,
        properties: (override || model.rate).properties
      }
    end

    private

    def obligation = options.fetch(:obligation)
    def period_from = model.started_at.utc
    def period_to = BillingSegment.inclusive_end(model.ended_at).utc
  end
end
