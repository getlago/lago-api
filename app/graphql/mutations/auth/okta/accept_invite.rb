# frozen_string_literal: true

module Mutations
  module Auth
    module Okta
      class AcceptInvite < BaseMutation
        graphql_name 'OktaAcceptInvite'
        description 'Accepts a membership invite with Okta Oauth'

        argument :code, String, required: true
        argument :invite_token, String, required: true

        type Types::Payloads::LoginUserType

        def resolve(code:, invite_token:)
          result = Auth::Okta::AcceptInviteService.call(code:, invite_token:)

          result.success? ? result : result_error(result)
        end
      end
    end
  end
end
