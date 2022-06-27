# frozen_string_literal: true
#
module V1
  class BillableMetricSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        description: model.description,
        aggregation_type: model.aggregation_type,
        created_at: model.created_at.iso8601,
        field_name: model.field_name
      }
    end
  end
end
