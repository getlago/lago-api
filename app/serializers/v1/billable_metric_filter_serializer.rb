# frozen_string_literal: true

module V1
  class BillableMetricFilterSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        key: model.key,
        values: model.values.sort,
      }
    end
  end
end
