# frozen_string_literal: true

module V2
  # An Entitlement::SubscriptionEntitlement of a contract read: the catalog plan values merged with the contract's own.
  class ContractEntitlementSerializer < ModelSerializer
    def serialize
      {
        lago_contract_id: model.contract.id,
        feature_code: model.code,
        source: model.plan_entitlement_id ? "plan" : "contract",
        values:
      }
    end

    private

    # In the order of the contract read: newest privilege first.
    def values
      model.privileges.map do |privilege|
        {
          privilege_code: privilege.code,
          value: Utils::Entitlement.cast_value(privilege.value, privilege.value_type),
          plan_value: Utils::Entitlement.cast_value(privilege.plan_value, privilege.value_type),
          source: privilege.sub_entitlement_value_id ? "contract" : "plan"
        }
      end
    end
  end
end
