# frozen_string_literal: true

module Types
  module AppliedCoupons
    class Object < Types::BaseObject
      graphql_name 'AppliedCoupon'

      field :id, ID, null: false
      field :coupon, Types::Coupons::Object, null: false

      field :amount_cents, Integer, null: false
      field :amount_currency, Types::CurrencyEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
