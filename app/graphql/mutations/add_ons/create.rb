# frozen_string_literal: true

module Mutations
  module AddOns
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateAddOn'
      description 'Creates a new add-on'

      input_object_class Types::AddOns::CreateInput

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
