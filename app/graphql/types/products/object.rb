# frozen_string_literal: true

module Types
  module Products
    class Object < Types::BaseObject
      graphql_name 'Product'

      field :id, ID, null: false
      field :organization, Types::OrganizationType

      field :name, String, null: false

      field :product_items, [Types::ProductItems::Object]

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
