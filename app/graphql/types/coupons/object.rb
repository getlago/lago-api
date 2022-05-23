# frozen_string_literal: true

module Types
  module Coupons
    class Object < Types::BaseObject
      graphql_name 'Coupon'

      field :id, ID, null: false
      field :organization, Types::OrganizationType

      field :name, String, null: false
      field :code, String, null: true
      field :status, Types::Coupons::StatusEnum, null: false
      field :amount_cents, Integer, null: false
      field :amount_currency, Types::CurrencyEnum, null: false

      field :expiration, Types::Coupons::ExpirationEnum, null: false
      field :expiration_duration, Integer, null: true
      field :expiration_date, GraphQL::Types::ISO8601Date, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :terminated_at, GraphQL::Types::ISO8601DateTime, null: true

      field :customer_count, Integer, null: false, description: 'Number of customers using this coupon'

      field :can_be_deleted, Boolean, null: false do
        description 'Check if coupon is deletable'
      end

      def customer_count
        0 # TODO: Add it with logic to assign coupon to a customer
      end

      def can_be_deleted
        object.deletable?
      end

      def expiration_date
        return unless object.expiration_duration

        object.created_at.to_date + object.expiration_duration.days
      end
    end
  end
end
