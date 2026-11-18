# frozen_string_literal: true

module V2
  module Entitlement
    class FeatureSerializer < ModelSerializer
      timestamps :created_at, :updated_at, :deleted_at

      # Not in webhooks: the feature.* webhooks keep the v1 payload.
      expandable :privileges, serializer: ::V2::Entitlement::PrivilegeSerializer

      def serialize
        {
          lago_id: model.id,
          code: model.code,
          name: model.name,
          description: model.description
        }
      end

      private

      # Newest first, as the association has no order. Sorted in memory, so a preloaded association costs no query.
      def privileges
        model.privileges.sort_by { [-it.created_at.to_r, it.id] }
      end
    end
  end
end
