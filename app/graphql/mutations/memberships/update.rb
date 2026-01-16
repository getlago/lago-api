# frozen_string_literal: true

module Mutations
  module Memberships
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "organization:members:update"

      graphql_name "UpdateMembership"
      description "Update a membership"

      input_object_class Types::Memberships::UpdateInput
      type Types::MembershipType

      def resolve(**args)
        membership = current_organization.memberships.find_by(id: args[:id])
        roles = args[:roles].presence || [args[:role]]
        result = ::Memberships::UpdateService.call(membership:, params: {roles:})
        result.success? ? result.membership : result_error(result)
      end
    end
  end
end
