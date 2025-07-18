# frozen_string_literal: true

module V1
  module Entitlement
    class SubscriptionEntitlementsCollectionSerializer < CollectionSerializer
      def serialize_models
        collection.group_by(&:feature_code).map do |feature_code, feature_entitlements|
          first_entitlement = feature_entitlements.first

          {
            code: feature_code,
            name: first_entitlement.feature_name,
            description: first_entitlement.feature_description,
            privileges: feature_entitlements.map do |e|
              {
                code: e.privilege_code,
                name: e.privilege_name,
                value_type: e.privilege_value_type,
                config: e.privilege_config,
                value: cast_value(e.privilege_override_value.presence || e.privilege_plan_value, e.privilege_value_type),
                plan_value: cast_value(e.privilege_plan_value, e.privilege_value_type),
                override_value: cast_value(e.privilege_override_value, e.privilege_value_type)
              }
            end.index_by { it[:code] },
            overrides: feature_entitlements.filter_map do |e|
              [e.privilege_code, cast_value(e.privilege_override_value, e.privilege_value_type)] unless e.privilege_override_value.nil?
            end.to_h
          }
        end
      end

      private

      def cast_value(value, type)
        return nil if value.blank?

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
