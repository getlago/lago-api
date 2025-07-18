# frozen_string_literal: true

module Types
  module Entitlement
    class SubscriptionEntitlementPrivilegeObject < Types::BaseObject
      field :code, String, null: false
      field :value, String, null: false

      def code
        object.privilege.code
      end
    end
  end
end
