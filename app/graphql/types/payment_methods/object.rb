# frozen_string_literal: true

module Types
  module PaymentMethods
    class Object < Types::BaseObject
      graphql_name "PaymentMethod"

      field :id, ID, null: false

      field :customer, Types::Customers::Object, null: false
      field :payment_provider, Types::PaymentProviders::ProviderTypeEnum, null: true
      field :payment_provider_code, String, null: true
      field :is_default, Boolean, null: false
      field :provider_customer_id, ID, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: true
    end
  end
end
