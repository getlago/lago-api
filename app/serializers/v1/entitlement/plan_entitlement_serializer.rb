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
        model.values.map do |ev|
          {
            code: ev.privilege.code,
            name: ev.privilege.name,
            value_type: ev.privilege.value_type,
            value: cast_value(ev.value, ev.privilege.value_type),
            config: ev.privilege.config
          }
        end.index_by { it[:code] }
      end

      def cast_value(value, type)
        case type
        when "integer"
          value.to_i
        when "boolean"
          ActiveModel::Type::Boolean.new.cast(value)
        else
          value
        end
      end
    end
  end
end
