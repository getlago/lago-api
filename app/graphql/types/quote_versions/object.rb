# frozen_string_literal: true

module Types
  module QuoteVersions
    class Object < Types::BaseObject
      graphql_name "QuoteVersion"

      field :approved_at, GraphQL::Types::ISO8601DateTime, null: true
      field :billing_items, GraphQL::Types::JSON, null: true
      field :content, String, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType, null: false
      field :quote, Types::Quotes::Object, null: false
      field :share_token, String, null: true
      field :status, Types::QuoteVersions::StatusEnum, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :version, Integer, null: false
      field :void_reason, Types::QuoteVersions::VoidReasonEnum, null: true
      field :voided_at, GraphQL::Types::ISO8601DateTime, null: true
      # TODO: field :order_form, Types::OrderForms::Object, null: true

      def quote
        dataloader
          .with(Sources::ActiveRecordAssociation, :quote)
          .load(object)
      end

      def organization
        dataloader
          .with(Sources::ActiveRecordAssociation, :organization)
          .load(object)
      end
    end
  end
end
