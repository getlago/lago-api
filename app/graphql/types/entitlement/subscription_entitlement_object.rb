# frozen_string_literal: true

module Types
  module Entitlement
    class SubscriptionEntitlementObject < Types::BaseObject
      graphql_name "SubscriptionEntitlement"

      field :code, String, null: false
      field :description, String, null: true
      field :name, String, null: false
      field :privileges, [SubscriptionEntitlementPrivilegeObject], null: false

      # TODO: Remove to avoid N+1, all feature attributes are already part of the SubscriptionEntitlement
      field :feature, Types::Entitlement::FeatureObject, null: false

      def privileges
        object.privileges.sort_by(&:created_at)
      end
    end
  end
end
