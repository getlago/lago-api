# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Mutations
  module CustomerPortal
    class UpdateCustomer < BaseMutation
      include AuthenticableCustomerPortalUser

      graphql_name "UpdateCustomerPortalCustomer"
      description "Update customer data from Customer Portal"

      input_object_class Types::CustomerPortal::Customers::UpdateInput
      type Types::CustomerPortal::Customers::Object

      def resolve(**args)
        result = ::CustomerPortal::CustomerUpdateService.call(
          customer: context[:customer_portal_user],
          args:
        )

        result.success? ? result.customer : result_error(result)
      end
    end
  end
end
