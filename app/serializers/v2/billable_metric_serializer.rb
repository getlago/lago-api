# frozen_string_literal: true

module V2
  # V1's fields plus updated_at and deleted_at, without its filters, so that the record stays flat, nor its
  # counters, which V1 renders as constant zeros.
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
        created_at: format_time(model.created_at),
        field_name: model.field_name,
        expression: model.expression,
        updated_at: format_time(model.updated_at),
        deleted_at: format_time(model.deleted_at)
      }
    end
  end
end
