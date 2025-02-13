# frozen_string_literal: true

module Mutations
  module Invites
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "organization:members:update"

      graphql_name "UpdateInvite"
      description "Update an invite"

      argument :id, ID, required: true
      argument :role, Types::Memberships::RoleEnum, required: true

      type Types::Invites::Object

      def resolve(**args)
        invite = current_organization.invites.pending.find_by(id: args[:id])
        result = ::Invites::UpdateService.call(invite:, params: args)
        result.success? ? result.invite : result_error(result)
      end
    end
  end
end
