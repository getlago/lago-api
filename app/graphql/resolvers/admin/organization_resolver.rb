# frozen_string_literal: true

module Resolvers
  module Admin
    class OrganizationResolver < Resolvers::BaseResolver
      include AuthenticableAdminUser

      description "Get a single organization by ID (admin only)"

      argument :organization_id, ID, required: true

      type Types::Admin::OrganizationType, null: true

      def resolve(organization_id:)
        Organization.find_by(id: organization_id)
      end
    end
  end
end
