# frozen_string_literal: true

module Types
  module ProductFilters
    class Object < Types::BaseObject
      graphql_name "ProductFilter"
      description "Base product filter"

      dataload_association :product

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :code, String, null: false
      field :description, String, null: true
      field :invoice_display_name, String, null: true
      field :name, String, null: false

      field :product, Types::Products::Object, null: false
      field :values, [Types::ProductFilterValues::Object], null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
