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

      # Creation order, as the association has none. It has no inverse either, so each privilege gets
      # its feature here rather than loading it again for feature_code.
      def privileges
        model.privileges.reorder(:created_at, :id).to_a.each { it.association(:feature).inversed_from(model) }
      end
    end
  end
end
