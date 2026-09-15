# frozen_string_literal: true

module Mutations
  module Invites
    class Accept < BaseMutation
      graphql_name "AcceptInvite"
      description "Accepts a new Invite"

      # NOTE: Older front-ends still send this argument. The email comes from the invitation
      #       token, so it has never been read.
      argument :email, String,
        required: false,
        deprecation_reason: "The email is resolved from the invitation token."
      argument :password, String, required: true
      argument :token, String, required: true, description: "Uniq token of the Invite"

      type Types::Payloads::RegisterUserType

      def resolve(**args)
        result = ::Invites::AcceptService.new.call(**args.merge(login_method: ::Organizations::AuthenticationMethods::EMAIL_PASSWORD))

        result.success? ? result : result_error(result)
      end
    end
  end
end
