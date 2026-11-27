# frozen_string_literal: true

module Types
  module Entitlement
    class SubscriptionEntitlementPrivilegeObject < Types::BaseObject
      field :code, String, null: false
      field :config, Types::Entitlement::PrivilegeConfigObject, null: false
      field :name, String, null: true
      field :value_type, Types::Entitlement::PrivilegeValueTypeEnum, null: false

      field :value, String, null: true

      def value
        # NOTE: Booleans are stored as `"true"`/`"false"`, but rows written before that hold `"t"`/`"f"`.
        #       We convert them to full words, as string, for the frontend
        if object.value_type == "boolean"
          return "false" if object.value == "f"
          return "true" if object.value == "t"
        end

        object.value
      end
    end
  end
end
