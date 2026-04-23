# frozen_string_literal: true

module Resolvers
  module Admin
    class OrganizationResolver < Resolvers::BaseResolver
      include AuthenticableStaffUser

      description "Fetch one organization across all tenants (Lago staff only)"

      argument :id, ID, required: true

      type Types::Admin::OrganizationType, null: true

      def resolve(id:)
        organization = ::Organization.find_by(id: id)
        return not_found_error(resource: "organization") if organization.blank?

        organization
      end
    end
  end
end
