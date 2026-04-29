# frozen_string_literal: true

module Types
  module QuoteVersions
    class Object < Types::BaseObject
      graphql_name "QuoteVersion"

      field :id, ID, null: false
      field :status, String, null: false
      field :version, Integer, null: false
      field :billing_items, GraphQL::Types::JSON, null: true
      field :content, String, null: true
      field :share_token, String, null: true
      field :approved_at, GraphQL::Types::ISO8601DateTime, null: true
      field :voided_at, GraphQL::Types::ISO8601DateTime, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :quote_id, ID, null: false
    end
  end
end
