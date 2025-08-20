# frozen_string_literal: true

module Types
  module Entitlement
    class SubscriptionEntitlementPrivilegeObject < Types::BaseObject
      field :code, String, null: false
      field :config, Types::Entitlement::PrivilegeConfigObject, null: false
      field :name, String, null: true
      field :value_type, Types::Entitlement::PrivilegeValueTypeEnum, null: false

      field :value, String, null: true
    end
  end
end
