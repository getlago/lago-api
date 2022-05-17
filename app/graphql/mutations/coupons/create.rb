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

      # NOTE: Fixed amount coupons
      argument :amount_cents, GraphQL::Types::BigInt, required: false
      argument :amount_currency, Types::CurrencyEnum, required: false

      # NOTE: Free days coupons
      argument :day_count, Integer, required: false

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
