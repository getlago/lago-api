# frozen_string_literal: true

module V2
  class BillableMetricFilterSerializer < ModelSerializer
    timestamps :created_at, :updated_at, :deleted_at

    def serialize
      {
        lago_id: model.id,
        key: model.key,
        values: model.values.sort
      }
    end
  end
end
