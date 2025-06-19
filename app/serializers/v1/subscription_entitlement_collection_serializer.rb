# frozen_string_literal: true

module V1
  class SubscriptionEntitlementCollectionSerializer < CollectionSerializer
    def serialize_models
      collection.reject(&:removed).group_by(&:feature).transform_values do
        it.filter_map do
          next unless it.privilege
          [it.privilege.code, {pv: it.privilege_plan_value, v: it.privilege_override_value, code: it.privilege.code}]
        end.to_h
      end

      #   .map do |model|
      #   model_serializer.new(model, options).serialize
      # end
    end
  end
end
