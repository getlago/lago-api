# frozen_string_literal: true

module Types
  module Entitlement
    class SubscriptionEntitlementPrivilegeObject < Types::BaseObject
      field :code, String, null: false
      field :config, GraphQL::Types::JSON, null: false
      field :name, String, null: true
      field :override_value, String, null: true
      field :plan_value, String, null: true
      field :value, String, null: true
      field :value_type, Types::Entitlement::PrivilegeValueTypeEnum, null: false
    end
  end
end
