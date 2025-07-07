# frozen_string_literal: true

module Types
  module Entitlement
    class FeatureObject < Types::BaseObject
      field :id, ID, null: false

      field :code, String, null: false
      field :description, String
      field :name, String

      field :privileges, [Types::Entitlement::PrivilegeObject], null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
