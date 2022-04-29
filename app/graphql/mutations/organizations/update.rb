# frozen_string_literal: true

module Mutations
  module Organizations
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'UpdateOrganization'
      description 'Updates an Organization'

      argument :webhook_url, String, required: false
      argument :vat_rate, Float, required: false

      type Types::OrganizationType

      def resolve(**args)
        validate_organization!

        result = ::Organizations::UpdateService
          .new(current_organization)
          .update(**args)

        result.success? ? result.organization : result_error(result)
      end
    end
  end
end
