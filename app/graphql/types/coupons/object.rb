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
      field :coupon_type, Types::Coupons::CouponTypeEnum, null: false
      field :amount_cents, Integer, null: true
      field :amount_currency, Types::CurrencyEnum, null: true
      field :percentage_rate, Float, null: true
      field :frequency, Types::Coupons::FrequencyEnum, null: false
      field :frequency_duration, Integer, null: true

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
        object.applied_coupons.active.count
      end

      def can_be_deleted
        object.deletable?
      end
    end
  end
end
