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

    # A deleted entitlement is rendered with the values it had before the delete, which the caller passes in
    # `values`: they are discarded with it.
    def values
      options[:values] || kept_values
    end

    # Newest privilege first, ties by privilege id, as Feature#ordered_privileges, so that the order does not
    # depend on when each value was written. Sorted in Ruby so that a preloaded association is not queried again.
    def kept_values
      model.values.select(&:privilege)
        .sort { |a, b| [b.privilege.created_at, a.privilege.id] <=> [a.privilege.created_at, b.privilege.id] }
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
