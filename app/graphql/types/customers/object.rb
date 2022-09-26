# frozen_string_literal: true

module Types
  module Customers
    class Object < Types::BaseObject
      graphql_name 'Customer'

      field :id, ID, null: false

      field :external_id, String, null: false
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
      field :currency, Types::CurrencyEnum, null: true
      field :payment_provider, Types::PaymentProviders::ProviderTypeEnum, null: true

      field :stripe_customer, Types::PaymentProviderCustomers::Stripe, null: true
      field :subscriptions, [Types::Subscriptions::Object]

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :has_active_wallet, Boolean, null: false, description: 'Define if a customer has an active wallet'
      field :active_subscription_count, Integer, null: false, description: 'Number of active subscriptions per customer'

      field :can_be_deleted, Boolean, null: false do
        description 'Check if customer is deletable'
      end

      field :can_edit_attributes, Boolean, null: false do
        description 'Check if customer attributes are editable'
      end

      def can_be_deleted
        object.deletable?
      end

      def has_active_wallet
        object.wallets.active.any?
      end

      def active_subscription_count
        object.active_subscriptions.count
      end

      def can_edit_attributes
        object.editable?
      end
    end
  end
end
