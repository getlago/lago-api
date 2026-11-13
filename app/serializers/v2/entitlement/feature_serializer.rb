# frozen_string_literal: true

module V2
  module Entitlement
    class FeatureSerializer < ModelSerializer
      timestamps :created_at, :updated_at, :deleted_at

      def serialize
        {
          lago_id: model.id,
          code: model.code,
          name: model.name,
          description: model.description
        }
      end
    end
  end
end
