# frozen_string_literal: true

module Mutations
  module Auth
    module EntraId
      class AcceptInvite < BaseMutation
        graphql_name "EntraIdAcceptInvite"
        description "Accepts a membership invite with Entra ID Oauth"

        input_object_class Types::Auth::EntraId::AcceptInviteInput

        type Types::Payloads::LoginUserType

        def resolve(code:, invite_token:, state:)
          result = ::Auth::EntraId::AcceptInviteService.call(code:, invite_token:, state:)

          result.success? ? result : result_error(result)
        end
      end
    end
  end
end
