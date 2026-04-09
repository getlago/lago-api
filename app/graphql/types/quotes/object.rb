# frozen_string_literal: true

module Types
  module Quotes
    class Object < Types::BaseObject
      graphql_name "Quote"

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :current_version, Types::QuoteVersions::Object, null: false
      field :customer, Types::Customers::Object, null: false
      field :id, ID, null: false
      field :number, String, null: false
      field :order_type, Types::Quotes::OrderTypeEnum, null: false
      field :organization, Types::Organizations::OrganizationType, null: false
      field :owners, [Types::UserType], null: true
      field :subscription, Types::Subscriptions::Object, null: true
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :versions, [Types::QuoteVersions::Object], null: false

      def customer
        dataloader
          .with(Sources::ActiveRecordAssociation, :customer)
          .load(object)
      end

      def organization
        dataloader
          .with(Sources::ActiveRecordAssociation, :organization)
          .load(object)
      end

      def subscription
        dataloader
          .with(Sources::ActiveRecordAssociation, :subscription)
          .load(object)
      end

      def owners
        dataloader
          .with(Sources::ActiveRecordAssociation, :owners)
          .load(object)
      end

      def versions
        dataloader
          .with(Sources::ActiveRecordAssociation, :versions)
          .load(object)
      end

      def current_version
        dataloader
          .with(Sources::ActiveRecordAssociation, :current_version)
          .load(object)
      end
    end
  end
end
