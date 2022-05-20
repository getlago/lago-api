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
      argument :amount_cents, Integer, required: true
      argument :amount_currency, Types::CurrencyEnum, required: true

      argument :expiration, Types::Coupons::ExpirationEnum, required: true
      argument :expiration_duration, Integer, required: false

      type Types::Coupons::Object

      def resolve(**args)
        result = ::Coupons::UpdateService.new(context[:current_user])
          .update(**args)

        result.success? ? result.coupon : result_error(result)
      end
    end
  end
end
