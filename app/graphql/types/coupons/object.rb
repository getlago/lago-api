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
      field :reusable, Boolean, null: false

      field :expiration, Types::Coupons::ExpirationEnum, null: false
      field :expiration_at, GraphQL::Types::ISO8601DateTime, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :terminated_at, GraphQL::Types::ISO8601DateTime, null: true

      field :customer_count, Integer, null: false, description: 'Number of customers using this coupon'

      field :can_be_deleted, Boolean, null: false do
        description 'Check if coupon is deletable'
      end

      def customer_count
        object.applied_coupons.active.select(:customer_id).distinct.count
      end

      def can_be_deleted
        object.deletable?
      end

      # NOTE: Legacy fields, will be removed when releasing the timezone feature
      field :expiration_date, GraphQL::Types::ISO8601Date, null: true

      def expiration_date
        object.expiration_at&.to_date
      end
    end
  end
end
