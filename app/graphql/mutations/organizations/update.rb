# frozen_string_literal: true

module Mutations
  module Organizations
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'UpdateOrganization'
      description 'Updates an Organization'

      argument :webhook_url, String, required: false
      argument :logo, String, required: false
      argument :legal_name, String, required: false
      argument :legal_number, String, required: false
      argument :email, String, required: false
      argument :address_line1, String, required: false
      argument :address_line2, String, required: false
      argument :state, String, required: false
      argument :zipcode, String, required: false
      argument :city, String, required: false
      argument :country, Types::CountryCodeEnum, required: false
      argument :timezone, Types::TimezoneEnum, required: false
      argument :billing_configuration, Types::Organizations::BillingConfigurationInput, required: false

      type Types::OrganizationType

      def resolve(**args)
        validate_organization!

        result = ::Organizations::UpdateService.call(organization: current_organization, params: args)
        result.success? ? result.organization : result_error(result)
      end
    end
  end
end
