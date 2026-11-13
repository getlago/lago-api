# frozen_string_literal: true

module V2
  module Entitlement
    class PrivilegeSerializer < ModelSerializer
      timestamps :created_at, :updated_at, :deleted_at

      def serialize
        {
          lago_id: model.id,
          feature_code: model.feature.code,
          code: model.code,
          name: model.name,
          value_type: model.value_type,
          select_options:
        }
      end

      private

      # Only a select privilege holds options in its config; other types have an empty config.
      def select_options
        (model.value_type == "select") ? model.config["select_options"] : nil
      end
    end
  end
end
