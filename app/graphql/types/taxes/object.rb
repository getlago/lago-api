# frozen_string_literal: true

module Types
  module Taxes
    class Object < Types::BaseObject
      graphql_name 'Tax'

      field :id, ID, null: false
      field :organization, Types::OrganizationType

      field :code, String, null: false
      field :description, String, null: true
      field :name, String, null: false
      field :rate, Float, null: false

      field :applied_to_organization, Boolean, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :customers_count, Integer, null: false, description: 'Number of customers using this tax'
    end
  end
end
