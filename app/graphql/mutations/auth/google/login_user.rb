# frozen_string_literal: true

# Mutations::Auth::Google::LoginUser Mutation
module Mutations
  module Auth
    module Google
      class LoginUser < BaseMutation
        graphql_name "GoogleLoginUser"
        description "Opens a session for an existing user with Google Oauth"

        input_object_class Types::Auth::Google::LoginUserInput

        type Types::Payloads::LoginUserType

        def resolve(code:, state: nil, state_secret: nil)
          result = ::Auth::GoogleService.call(:login, code, state:, state_secret:)
          result.success? ? result : result_error(result)
        end
      end
    end
  end
end
