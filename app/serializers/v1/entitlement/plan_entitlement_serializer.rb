# frozen_string_literal: true

module V1
  module Entitlement
    class PlanEntitlementSerializer < ModelSerializer
      def serialize
        {
          code: model.feature.code,
          name: model.feature.name,
          description: model.feature.description,
          privileges:
        }
      end

      private

      def privileges
        model.values.filter_map do |ev|
          next if ev.privilege.nil?

          {
            code: ev.privilege.code,
            name: ev.privilege.name,
            value_type: ev.privilege.value_type,
            value: Utils::Entitlement.cast_value(ev.value, ev.privilege.value_type),
            config: ev.privilege.config
          }
        end
      end
    end
  end
end
