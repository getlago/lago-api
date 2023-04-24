# frozen_string_literal: true

module Mutations
  module Coupons
    class Update < BaseMutation
      include AuthenticableApiUser

      graphql_name 'UpdateCoupon'
      description 'Update an existing coupon'

      argument :amount_cents, GraphQL::Types::BigInt, required: false
      argument :amount_currency, Types::CurrencyEnum, required: false
      argument :code, String, required: false
      argument :coupon_type, Types::Coupons::CouponTypeEnum, required: true
      argument :frequency, Types::Coupons::FrequencyEnum, required: true
      argument :frequency_duration, Integer, required: false
      argument :id, String, required: true
      argument :name, String, required: true
      argument :percentage_rate, Float, required: false
      argument :reusable, Boolean, required: false

      argument :applies_to, Types::Coupons::LimitationInput, required: false

      argument :expiration, Types::Coupons::ExpirationEnum, required: true
      argument :expiration_at, GraphQL::Types::ISO8601DateTime, required: false

      type Types::Coupons::Object

      def resolve(**args)
        coupon = context[:current_user].coupons.find_by(id: args[:id])
        result = ::Coupons::UpdateService.call(coupon:, params: args)
        result.success? ? result.coupon : result_error(result)
      end
    end
  end
end
