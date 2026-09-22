# frozen_string_literal: true

module Types
  module UsageAttributionTypes
    class Object < Types::BaseObject
      graphql_name "UsageAttributionType"
      description "Base usage attribution type"

      dataload_association :parent, :children

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :attribution_keys, [String], null: false
      field :code, String, null: false
      field :name, String, null: true
      field :role, Types::UsageAttributionTypes::RoleEnum, null: false

      field :parent, Types::UsageAttributionTypes::Object, null: true
      field :children, [Types::UsageAttributionTypes::Object], null: false, description: "Child types, empty for a leaf or a flat type"

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
