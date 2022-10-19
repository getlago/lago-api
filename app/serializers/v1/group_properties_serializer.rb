# frozen_string_literal: true

module V1
  class GroupPropertiesSerializer < ModelSerializer
    def serialize
      {
        group_id: model.group_id,
        values: model.values,
      }
    end
  end
end
