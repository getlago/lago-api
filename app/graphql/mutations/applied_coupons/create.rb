# frozen_string_literal: true

module Mutations
  module AppliedCoupons
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateAppliedCoupon'
      description 'Assigns a Coupon to a Customer'

      argument :coupon_id, ID, required: true
      argument :customer_id, ID, required: true

      argument :amount_cents, GraphQL::Types::BigInt, required: false
      argument :amount_currency, Types::CurrencyEnum, required: false
      argument :percentage_rate, Float, required: false
      argument :frequency, Types::Coupons::FrequencyEnum, required: false
      argument :frequency_duration, Integer, required: false

      type Types::AppliedCoupons::Object

      def resolve(**args)
        validate_organization!

        result = ::AppliedCoupons::CreateService
          .new(context[:current_user])
          .create(**args.merge(organization_id: current_organization.id))

        result.success? ? result.applied_coupon : result_error(result)
      end
    end
  end
end
