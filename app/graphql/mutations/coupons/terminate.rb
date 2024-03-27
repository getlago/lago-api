# frozen_string_literal: true

module Mutations
  module Coupons
    class Terminate < BaseMutation
      include AuthenticableApiUser

      graphql_name "TerminateCoupon"
      description "Deletes a coupon"

      argument :id, ID, required: true

      type Types::Coupons::Object

      def resolve(id:)
        result = ::Coupons::TerminateService.new(context[:current_user]).terminate(id)

        result.success? ? result.coupon : result_error(result)
      end
    end
  end
end
