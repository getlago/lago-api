# frozen_string_literal: true

module Mutations
  module Invites
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "organization:members:update"

      graphql_name "UpdateInvite"
      description "Update an invite"

      input_object_class Types::Invites::UpdateInput
      type Types::Invites::Object

      def resolve(**args)
        invite = current_organization.invites.pending.find_by(id: args[:id])
        roles = args[:roles].presence || [args[:role]]
        result = ::Invites::UpdateService.call(invite:, params: {roles:})
        result.success? ? result.invite : result_error(result)
      end
    end
  end
end
