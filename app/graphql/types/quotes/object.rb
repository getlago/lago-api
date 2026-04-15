# frozen_string_literal: true

module Types
  module Quotes
    class Object < Types::BaseObject
      graphql_name "Quote"

      field :id, ID, null: false
      field :status, String, null: false
      field :order_type, String, null: false
      field :number, String, null: false
      field :version, Integer, null: false
      field :currency, String, null: true
      field :description, String, null: true
      field :content, String, null: true
      field :legal_text, String, null: true
      field :internal_notes, String, null: true
      field :auto_execute, Boolean, null: false
      field :billing_items, GraphQL::Types::JSON, null: true
      field :commercial_terms, GraphQL::Types::JSON, null: true
      field :contacts, GraphQL::Types::JSON, null: true
      field :metadata, GraphQL::Types::JSON, null: true
      field :approved_at, GraphQL::Types::ISO8601DateTime, null: true
      field :voided_at, GraphQL::Types::ISO8601DateTime, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
