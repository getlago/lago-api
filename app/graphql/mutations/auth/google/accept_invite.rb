# frozen_string_literal: true

module Mutations
  module Auth
    module Google
      class AcceptInvite < BaseMutation
        graphql_name "GoogleAcceptInvite"
        description "Accepts a membership invite with Google Oauth"

        input_object_class Types::Auth::Google::AcceptInviteInput

        type Types::Payloads::RegisterUserType

        def resolve(code:, invite_token:, state: nil, state_secret: nil)
          result = ::Auth::GoogleService.call(:accept_invite, code, invite_token, state:, state_secret:)

          result.success? ? result : result_error(result)
        end
      end
    end
  end
end
