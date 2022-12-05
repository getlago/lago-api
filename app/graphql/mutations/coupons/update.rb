# frozen_string_literal: true

module Mutations
  module Coupons
    class Update < BaseMutation
      include AuthenticableApiUser

      graphql_name 'UpdateCoupon'
      description 'Update an existing coupon'

      argument :id, String, required: true
      argument :name, String, required: true
      argument :code, String, required: false
      argument :coupon_type, Types::Coupons::CouponTypeEnum, required: true
      argument :amount_cents, Integer, required: false
      argument :amount_currency, Types::CurrencyEnum, required: false
      argument :percentage_rate, Float, required: false
      argument :frequency, Types::Coupons::FrequencyEnum, required: true
      argument :frequency_duration, Integer, required: false
      argument :reusable, Boolean, required: false

      argument :expiration, Types::Coupons::ExpirationEnum, required: true
      argument :expiration_date, GraphQL::Types::ISO8601Date, required: false

      type Types::Coupons::Object

      def resolve(**args)
        result = ::Coupons::UpdateService.new(context[:current_user])
          .update(**args)

        result.success? ? result.coupon : result_error(result)
      end
    end
  end
end
