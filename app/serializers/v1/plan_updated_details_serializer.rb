# frozen_string_literal: true

module V1
  class PlanUpdatedDetailsSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        code: model.code,
        changes: options[:changes] || {}
      }
    end
  end
end
