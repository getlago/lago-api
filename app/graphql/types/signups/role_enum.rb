# frozen_string_literal: true

module Types
  module Signups
    class RoleEnum < Types::BaseEnum
      graphql_name "SignupRoleEnum"
      description "The role a user gives at signup Step 3, sent to analytics only"

      ::Signups::CreateOrganizationService::ROLES.each { value it }
    end
  end
end
