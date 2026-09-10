# frozen_string_literal: true

module Types
  module UsageAttributionTypes
    class Object < Types::BaseObject
      graphql_name "UsageAttributionType"
      description "Base usage attribution type"

      dataload_association :parent

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :attribution_key, String, null: false
      field :code, String, null: false
      field :name, String, null: true
      field :role, Types::UsageAttributionTypes::RoleEnum, null: false

      field :parent, Types::UsageAttributionTypes::Object, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
