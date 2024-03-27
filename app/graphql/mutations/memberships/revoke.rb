# frozen_string_literal: true

module Mutations
  module Memberships
    class Revoke < BaseMutation
      include AuthenticableApiUser

      graphql_name "RevokeMembership"
      description "Revoke a membership"

      argument :id, ID, required: true

      type Types::MembershipType

      def resolve(id:)
        result = ::Memberships::RevokeService.new(context[:current_user]).call(id)

        result.success? ? result.membership : result_error(result)
      end
    end
  end
end
