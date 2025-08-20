# frozen_string_literal: true

module V1
  module Entitlement
    class SubscriptionEntitlementsCollectionSerializer < CollectionSerializer
      def initialize(collection, options = nil)
        super(collection, nil, options)
      end

      def serialize_models
        collection.sort_by(&:entitlement_created_at).group_by(&:feature_code).map do |feature_code, feature_entitlements|
          first_entitlement = feature_entitlements.first

          {
            code: feature_code,
            name: first_entitlement.feature_name,
            description: first_entitlement.feature_description,
            privileges: feature_entitlements.reject do |e|
              e.privilege_code.blank?
            end.sort_by(&:privilege_value_created_at).map do |e|
              {
                code: e.privilege_code,
                name: e.privilege_name,
                value_type: e.privilege_value_type,
                config: e.privilege_config,
                value: Utils::Entitlement.cast_value(e.privilege_override_value.presence || e.privilege_plan_value, e.privilege_value_type),
                plan_value: Utils::Entitlement.cast_value(e.privilege_plan_value, e.privilege_value_type),
                override_value: Utils::Entitlement.cast_value(e.privilege_override_value, e.privilege_value_type)
              }
            end,
            overrides: feature_entitlements.filter_map do |e|
              [e.privilege_code, Utils::Entitlement.cast_value(e.privilege_override_value, e.privilege_value_type)] unless e.privilege_override_value.nil?
            end.to_h
          }
        end
      end
    end
  end
end
