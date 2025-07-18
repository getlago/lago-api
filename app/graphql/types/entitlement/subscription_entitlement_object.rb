# frozen_string_literal: true

module Types
  module Entitlement
    class SubscriptionEntitlementObject < Types::BaseObject
      graphql_name "SubscriptionEntitlement"

      field :code, String, null: false
      field :privileges, [SubscriptionEntitlementPrivilegeObject], null: false, method: :values
      field :removed, Boolean, null: false, description: "Whether this feature is removed from the subscription"

      def code
        object.feature.code
      end

      def removed
        object.respond_to?(:removed) ? object.removed : false
      end
    end
  end
end
