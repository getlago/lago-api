# frozen_string_literal: true

module Mutations
  module Invites
    class JoinOrganization < BaseMutation
      include AuthenticableApiUser

      description "Joins the organization of an Invite as the authenticated user"

      argument :token, String, required: true, description: "Unique token of the Invite"

      type Types::MembershipType

      def resolve(token:)
        result = ::Invites::JoinService.call(
          token:,
          user: context[:current_user],
          login_method: context[:login_method]
        )

        result.success? ? result.membership : result_error(result)
      end
    end
  end
end
