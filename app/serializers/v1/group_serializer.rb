# frozen_string_literal: true

module V1
  class GroupSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        key: model.parent&.value,
        value: model.value,
      }
    end
  end
end
