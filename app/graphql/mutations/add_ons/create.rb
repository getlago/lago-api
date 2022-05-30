# frozen_string_literal: true

module Mutations
  module AddOns
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateAddOn'
      description 'Creates a new add-on'

      argument :name, String, required: true
      argument :code, String, required: true
      argument :description, String, required: false
      argument :amount_cents, Integer, required: true
      argument :amount_currency, Types::CurrencyEnum, required: true

      type Types::AddOns::Object

      def resolve(**args)
        validate_organization!

        result = ::AddOns::CreateService
          .new(context[:current_user])
          .create(**args.merge(organization_id: current_organization.id))

        result.success? ? result.add_on : result_error(result)
      end
    end
  end
end
