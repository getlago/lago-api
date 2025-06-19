# frozen_string_literal: true

module V1
  class SubscriptionEntitlementCollectionSerializer < CollectionSerializer
    def serialize_models
      collection.reject(&:removed).group_by(&:feature).transform_values do
        it.filter_map do
          next unless it.privilege
          PrivilegeWithValue.new(
            privilege: it.privilege,
            plan_value: it.privilege_plan_value,
            override_value: it.privilege_override_value
          )
        end
      end.map do |feature, privilege_with_value|
        {
          code: feature.code,
          name: feature.name,
          description: feature.description,
          privileges: privilege_with_value.map do |p|
            {
              code: p.code,
              name: p.name,
              value_type: p.value_type,
              value: p.value_casted,
              plan_value: p.plan_value_casted,
              override_value: p.override_value_casted
            }
          end.index_by { it[:code] },
          overrides: privilege_with_value.filter_map do |p|
            [p.code, p.override_value_casted] unless p.override_value.nil?
          end.to_h
        }
      end
    end
  end
end
