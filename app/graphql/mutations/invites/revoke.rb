# frozen_string_literal: true

module Mutations
  module Invites
    class Revoke < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'organization:members:delete'

      graphql_name 'RevokeInvite'
      description 'Revokes a invite'

      argument :id, ID, required: true

      type Types::Invites::Object

      def resolve(**args)
        result = ::Invites::RevokeService
          .new(context[:current_user])
          .call(**args.merge(current_organization:))

        result.success? ? result.invite : result_error(result)
      end
    end
  end
end
