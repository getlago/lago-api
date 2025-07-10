# frozen_string_literal: true

module Types
  module Entitlement
    class PlanEntitlementObject < Types::BaseObject
      graphql_name "PlanEntitlement"

      field :code, String, null: false
      field :description, String, null: true
      field :name, String, null: false
      field :privileges, [PlanEntitlementPrivilegeObject], null: false, method: :values

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
