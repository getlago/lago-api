# frozen_string_literal: true

module Types
  module AppliedCoupons
    class Object < Types::BaseObject
      graphql_name 'AppliedCoupon'

      field :id, ID, null: false
      field :coupon, Types::Coupons::Object, null: false

      field :amount_cents, Integer, null: true
      field :amount_currency, Types::CurrencyEnum, null: true

      field :percentage_rate, Float, null: true
      field :frequency, Types::Coupons::FrequencyEnum, null: false
      field :frequency_duration, Integer, null: true
      field :frequency_duration_remaining, Integer, null: true
      field :amount_cents_remaining, Integer, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :terminated_at, GraphQL::Types::ISO8601DateTime, null: false

      def amount_cents_remaining
        return nil if object.recurring?
        return nil if object.coupon.percentage?

        object.amount_cents - object.credits.sum(:amount_cents)
      end
    end
  end
end
