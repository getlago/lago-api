# frozen_string_literal: true

module V2
  # V1's scalar fields only: the filters and counters V1 embeds are left out, so the record stays flat.
  class BillableMetricSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        description: model.description,
        aggregation_type: model.aggregation_type,
        weighted_interval: model.weighted_interval,
        recurring: model.recurring,
        rounding_function: model.rounding_function,
        rounding_precision: model.rounding_precision,
        created_at: model.created_at.iso8601,
        field_name: model.field_name,
        expression: model.expression,
        **deleted_at_payload
      }
    end
  end
end
