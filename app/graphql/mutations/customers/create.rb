# frozen_string_literal: true

module Mutations
  module Customers
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "CreateCustomer"
      description "Creates a new customer"

      input_object_class Types::Customers::CreateCustomerInput

      type Types::Customers::Object

      def resolve(**args)
        validate_organization!

        result = ::Customers::CreateService
          .new(context[:current_user])
          .create(**args.merge(organization_id: current_organization.id))

        result.success? ? result.customer : result_error(result)
      end
    end
  end
end
