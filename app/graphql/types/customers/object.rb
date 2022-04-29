# frozen_string_literal: true

module Types
  module Customers
    class Object < Types::BaseObject
      graphql_name 'Customer'

      field :id, ID, null: false

      field :customer_id, String, null: false
      field :name, String

      field :country, Types::Customers::CountryCodeEnum, null: true
      field :address_line1, String, null: true
      field :address_line2, String, null: true
      field :state, String, null: true
      field :zipcode, String, null: true
      field :email, String, null: true
      field :city, String, null: true
      field :url, String, null: true
      field :phone, String, null: true
      field :logo_url, String, null: true
      field :legal_name, String, null: true
      field :legal_number, String, null: true
      field :vat_rate, Float, null: true

      field :subscriptions, [Types::Subscriptions::Object]

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :can_be_deleted, Boolean, null: false do
        description 'Check if customer is deletable'
      end

      def can_be_deleted
        object.deletable?
      end
    end
  end
end
