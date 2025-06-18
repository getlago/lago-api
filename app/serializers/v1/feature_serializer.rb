# frozen_string_literal: true

module V1
  class FeatureSerializer < ModelSerializer
    def serialize
      {
        code: model.code,
        name: model.name,
        description: model.description,
        privileges:
      }
    end

    def privileges
      model.privileges.map do |p|
        {
          code: p.code,
          name: p.name,
          value_type: p.value_type
        }
      end.index_by { it[:code] }
    end
  end
end
