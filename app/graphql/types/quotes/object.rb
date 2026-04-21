# frozen_string_literal: true

module Types
  module Quotes
    class Object < Types::BaseObject
      graphql_name "Quote"

      field :customer, Types::Customers::Object, null: false
      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType, null: false
      field :subscription, Types::Subscriptions::Object, null: true

      field :approved_at, GraphQL::Types::ISO8601DateTime, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :number, String, null: false
      field :order_type, Types::Quotes::OrderTypeEnum, null: false
      field :owners, [Types::UserType], null: true
      field :share_token, String, null: true
      field :status, Types::Quotes::StatusEnum, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :version, Integer, null: false
      field :void_reason, Types::Quotes::VoidReasonEnum, null: true
      field :voided_at, GraphQL::Types::ISO8601DateTime, null: true
    end
  end
end
