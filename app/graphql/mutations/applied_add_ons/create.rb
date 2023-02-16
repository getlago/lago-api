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

        customer = Customer.find_by(
          id: args[:customer_id],
          organization_id: current_organization.id,
        )

        add_on = AddOn.find_by(
          id: args[:add_on_id],
          organization_id: current_organization.id,
        )

        result = ::AppliedAddOns::CreateService.call(customer:, add_on:, params: args)
        result.success? ? result.applied_add_on : result_error(result)
      end
    end
  end
end
