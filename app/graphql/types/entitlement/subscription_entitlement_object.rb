# frozen_string_literal: true

module Types
  module Entitlement
    class SubscriptionEntitlementObject < Types::BaseObject
      graphql_name "SubscriptionEntitlement"

      field :code, String, null: false
      field :description, String, null: true
      field :feature, Types::Entitlement::FeatureObject, null: false
      field :name, String, null: false
      field :privileges, [SubscriptionEntitlementPrivilegeObject], null: false

      def code
        object.feature.code
      end

      def name
        object.feature.name
      end

      def description
        object.feature.description
      end
    end
  end
end
