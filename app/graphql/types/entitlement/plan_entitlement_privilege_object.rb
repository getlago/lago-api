# frozen_string_literal: true

module Types
  module Entitlement
    class PlanEntitlementPrivilegeObject < Types::BaseObject
      field :code, String, null: false
      field :config, Types::Entitlement::PrivilegeConfigObject, null: false
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

      def value
        # NOTE: Booleans are stored as `"true"`/`"false"`, but rows written before that hold `"t"`/`"f"`.
        #       We convert them to full words, as string, for the frontend
        if object.privilege.value_type == "boolean"
          return "false" if object.value == "f"
          return "true" if object.value == "t"
        end

        object.value
      end
    end
  end
end
