# frozen_string_literal: true

module Mutations
  module Coupons
    class Destroy < BaseMutation
      include AuthenticableApiUser

      graphql_name 'DestroyCoupon'
      description 'Deletes a coupon'

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        result = ::Coupons::DestroyService.new(context[:current_user]).destroy(id)

        result.success? ? result.coupon : result_error(result)
      end
    end
  end
end
