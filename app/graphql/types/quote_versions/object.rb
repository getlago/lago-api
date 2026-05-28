# frozen_string_literal: true

module Types
  module QuoteVersions
    class Object < Types::BaseObject
      graphql_name "QuoteVersion"

      field :approved_at, GraphQL::Types::ISO8601DateTime, null: true
      field :billing_items, GraphQL::Types::JSON, null: true
      field :content, String, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :currency, String, null: true
      field :end_date, GraphQL::Types::ISO8601Date, null: true
      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType, null: false
      field :quote, Types::Quotes::Object, null: false
      field :share_token, String, null: true
      field :start_date, GraphQL::Types::ISO8601Date, null: true
      field :status, Types::QuoteVersions::StatusEnum, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :version, Integer, null: false
      field :void_reason, Types::QuoteVersions::VoidReasonEnum, null: true
      field :voided_at, GraphQL::Types::ISO8601DateTime, null: true
      # TODO: field :order_form, Types::OrderForms::Object, null: true

      dataload_association :organization, :quote
    end
  end
end
