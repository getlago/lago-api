# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Entitlement
    class SubscriptionEntitlementObject < Types::BaseObject
      graphql_name "SubscriptionEntitlement"

      field :code, String, null: false
      field :description, String, null: true
      field :name, String, null: false
      field :privileges, [SubscriptionEntitlementPrivilegeObject], null: false
    end
  end
end
