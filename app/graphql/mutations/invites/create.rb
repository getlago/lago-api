# frozen_string_literal: true

module Mutations
  module Invites
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "organization:members:create"

      graphql_name "CreateInvite"
      description "Creates a new Invite"

      input_object_class Types::Invites::CreateInput
      type Types::Invites::Object

      def resolve(**args)
        result = ::Invites::CreateService.call(
          current_organization:,
          email: args[:email],
          roles: args[:roles].presence || [args[:role]]
        )

        result.success? ? result.invite : result_error(result)
      end
    end
  end
end
