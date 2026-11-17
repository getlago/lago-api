# frozen_string_literal: true

module V2
  class PlanEntitlementSerializer < ModelSerializer
    timestamps :created_at, :updated_at, :deleted_at

    def serialize
      {
        lago_id: model.id,
        plan_code: model.catalog_plan&.code,
        feature_code: model.feature.code,
        values:
      }
    end

    private

    # Newest privilege first, then by privilege id, so that the order does not depend on when each value
    # was written. Sorted in Ruby so that a preloaded association is not queried again.
    def values
      model.values.select(&:privilege)
        .sort_by { [it.privilege.created_at, it.privilege.id] }.reverse
        .map do |entitlement_value|
          privilege = entitlement_value.privilege

          {
            privilege_code: privilege.code,
            value: Utils::Entitlement.cast_value(entitlement_value.value, privilege.value_type)
          }
        end
    end
  end
end
