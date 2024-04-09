# frozen_string_literal: true

module Mutations
  module Invites
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateInvite'
      description 'Creates a new Invite'

      argument :email, String, required: true

      type Types::Invites::Object

      def resolve(**args)
        result = ::Invites::CreateService
          .new(context[:current_user])
          .call(**args.merge(current_organization:))

        result.success? ? result.invite : result_error(result)
      end
    end
  end
end
