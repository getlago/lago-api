# frozen_string_literal: true

module Mutations
  module Coupons
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateCoupon'
      description 'Creates a new Coupon'

      input_object_class Types::Coupons::CreateInput

      type Types::Coupons::Object

      def resolve(**args)
        validate_organization!

        result = ::Coupons::CreateService
          .new(context[:current_user])
          .create(args.merge(organization_id: current_organization.id))

        result.success? ? result.coupon : result_error(result)
      end
    end
  end
end
