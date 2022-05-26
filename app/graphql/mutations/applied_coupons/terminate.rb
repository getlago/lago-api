# frozen_string_literal: true

module Mutations
  module AppliedCoupons
    class Terminate < BaseMutation
      include AuthenticableApiUser

      graphql_name 'TerminateAppliedCoupon'
      description 'Unassign a coupon from a customer'

      argument :id, ID, required: true

      type Types::AppliedCoupons::Object

      def resolve(id:)
        result = ::AppliedCoupons::TerminateService
          .new(context[:current_user])
          .terminate(id)

        result.success? ? result.applied_coupon : result_error(result)
      end
    end
  end
end
