# frozen_string_literal: true

module Mutations
  module Memberships
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "organization:members:update"

      graphql_name "UpdateMembership"
      description "Update a membership"

      argument :id, ID, required: true
      argument :role, Types::Memberships::RoleEnum, required: true

      type Types::MembershipType

      def resolve(**args)
        membership = current_organization.memberships.find_by(id: args[:id])
        result = ::Memberships::UpdateService.call(membership:, params: args)
        result.success? ? result.membership : result_error(result)
      end
    end
  end
end
