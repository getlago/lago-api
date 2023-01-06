# frozen_string_literal: true

module Mutations
  module AppliedAddOns
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateAppliedAddOn'
      description 'Assigns an add-on to a Customer'

      argument :add_on_id, ID, required: true
      argument :customer_id, ID, required: true

      argument :amount_cents, GraphQL::Types::BigInt, required: false
      argument :amount_currency, Types::CurrencyEnum, required: false

      type Types::AppliedAddOns::Object

      def resolve(**args)
        validate_organization!

        result = ::AppliedAddOns::CreateService
          .new(context[:current_user])
          .create(**args.merge(organization_id: current_organization.id))

        result.success? ? result.applied_add_on : result_error(result)
      end
    end
  end
end
