# frozen_string_literal: true

module Types
  module Coupons
    class Object < Types::BaseObject
      graphql_name 'Coupon'

      field :id, ID, null: false
      field :organization, Types::OrganizationType

      field :name, String, null: false
      field :code, String, null: true
      field :coupon_type, Types::Coupons::CouponTypeEnum, null: false

      # NOTE: Fixed amount coupons
      field :amount_cents, GraphQL::Types::BigInt, null: true
      field :amount_currency, Types::CurrencyEnum, null: true

      # NOTE: Free days coupons
      field :day_count, Integer, null: true

      field :expiration, Types::Coupons::ExpirationEnum, null: false
      field :expiration_duration, Integer, null: true
      field :expiration_users, Integer, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :can_be_deleted, Boolean, null: false do
        description 'Check if coupon is deletable'
      end

      def can_be_deleted
        object.deletable?
      end
    end
  end
end
