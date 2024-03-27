# frozen_string_literal: true

module Resolvers
  class OrganizationResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description "Query the current organization"

    type Types::OrganizationType, null: true

    def resolve
      validate_organization!
      current_organization
    end
  end
end
