# frozen_string_literal: true

module Mutations
  module ApiKeys
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'developers:keys:manage'

      graphql_name 'CreateApiKey'
      description 'Creates a new API key'

      argument :name, String, required: false

      type Types::ApiKeys::Object

      def resolve(**args)
        result = ::ApiKeys::CreateService.call(args.merge(organization_id: current_organization.id))

        result.success? ? result.api_key : result_error(result)
      end
    end
  end
end
