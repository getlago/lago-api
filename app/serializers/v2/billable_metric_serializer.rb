# frozen_string_literal: true

module V2
  class BillableMetricSerializer < ModelSerializer
    timestamps :created_at, :updated_at, :deleted_at
    expandable :filters, serializer: ::V2::BillableMetricFilterSerializer

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
        field_name: model.field_name,
        expression: model.expression
      }
    end
  end
end
