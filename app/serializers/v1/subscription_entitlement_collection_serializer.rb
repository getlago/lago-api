# frozen_string_literal: true

module V1
  class SubscriptionEntitlementCollectionSerializer < CollectionSerializer
    def serialize_models
      collection.reject(&:removed).group_by(&:feature_id).map do |_feature_id, subscription_entitlements|
        {
          code: subscription_entitlements.first.feature_code,
          name: subscription_entitlements.first.feature_name,
          description: subscription_entitlements.first.feature_description,
          privileges: subscription_entitlements.filter_map do |p|
            next unless p.privilege_id
            {
              code: p.privilege_code,
              name: p.privilege_name,
              value_type: p.privilege_value_type,
              value: p.privilege_value_casted,
              plan_value: p.privilege_plan_value_casted,
              override_value: p.privilege_override_value_casted
            }
          end.index_by { it[:code] },
          overrides: subscription_entitlements.filter_map do |p|
            [p.privilege_code, p.privilege_override_value_casted] unless p.privilege_override_value.nil?
          end.to_h
        }
      end
    end
  end
end
