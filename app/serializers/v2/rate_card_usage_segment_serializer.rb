# frozen_string_literal: true

module V2
  class RateCardUsageSegmentSerializer < ModelSerializer
    timestamps :from_datetime, :to_datetime

    def serialize
      {
        rate_model: model.rate_model,
        rate_properties: model.rate_properties,
        units: model.units.to_s,
        events_count: model.events_count,
        amount_cents: model.amount_cents
      }
    end

    private

    def from_datetime = model.started_at

    def to_datetime = model.ended_at
  end
end
