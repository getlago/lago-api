# frozen_string_literal: true

module Mutations
  module Invites
    class Accept < BaseMutation
      include ThrottlesAuthAttempts

      graphql_name "AcceptInvite"
      description "Accepts a new Invite"

      argument :email, String, required: true
      argument :password, String, required: true
      argument :token, String, required: true, description: "Uniq token of the Invite"

      type Types::Payloads::RegisterUserType

      def resolve(**args)
        return too_many_attempts_error if ::Auth::AttemptsThrottle.hit!(:credentials_per_ip, client_ip)

        result = ::Invites::AcceptService.new.call(**args.merge(login_method: ::Organizations::AuthenticationMethods::EMAIL_PASSWORD))

        result.success? ? result : result_error(result)
      end
    end
  end
end
