# frozen_string_literal: true

module V1
  class MetadataSerializer < ModelSerializer
    def serialize
      return nil unless model

      model.value
    end
  end
end
