# frozen_string_literal: true

module Types
  module Entitlement
    class PlanEntitlementPrivilegeObject < Types::BaseObject
      field :code, String, null: false
      field :config, GraphQL::Types::JSON, null: false
      field :name, String, null: true
      field :value_type, Types::Entitlement::PrivilegeValueTypeEnum, null: false

      field :value, String, null: false

      def code
        object.privilege.code
      end

      def config
        object.privilege.config
      end

      def name
        object.privilege.name
      end

      def value_type
        object.privilege.value_type
      end
    end
  end
end
