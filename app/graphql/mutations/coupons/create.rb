# frozen_string_literal: true

module Mutations
  module Coupons
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateCoupon'
      description 'Creates a new Coupon'

      argument :name, String, required: true
      argument :code, String, required: false
      argument :coupon_type, Types::Coupons::CouponTypeEnum, required: true
      argument :amount_cents, Integer, required: false
      argument :amount_currency, Types::CurrencyEnum, required: false
      argument :percentage_rate, Float, required: false
      argument :frequency, Types::Coupons::FrequencyEnum, required: true
      argument :frequency_duration, Integer, required: false

      argument :expiration, Types::Coupons::ExpirationEnum, required: true
      argument :expiration_duration, Integer, required: false

      type Types::Coupons::Object

      def resolve(**args)
        validate_organization!

        result = ::Coupons::CreateService
          .new(context[:current_user])
          .create(**args.merge(organization_id: current_organization.id))

        result.success? ? result.coupon : result_error(result)
      end
    end
  end
end
