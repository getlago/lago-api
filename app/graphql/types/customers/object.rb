# frozen_string_literal: true

module Types
  module Customers
    class Object < Types::BaseObject
      graphql_name 'Customer'

      field :id, ID, null: false

      field :customer_id, String, null: false
      field :name, String
      field :sequential_id, String, null: false
      field :slug, String, null: false

      field :country, Types::CountryCodeEnum, null: true
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
      field :payment_provider, Types::PaymentProviders::ProviderTypeEnum, null: true

      field :stripe_customer, Types::PaymentProviderCustomers::Stripe, null: true
      field :subscriptions, [Types::Subscriptions::Object]

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :active_subscription_count, Integer, null: false, description: 'Number of active subscriptions per customer'

      field :can_be_deleted, Boolean, null: false do
        description 'Check if customer is deletable'
      end

      def can_be_deleted
        object.deletable?
      end

      def active_subscription_count
        object.active_subscriptions.count
      end
    end
  end
end
