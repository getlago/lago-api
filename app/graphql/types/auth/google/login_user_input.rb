# frozen_string_literal: true

module Types
  module Auth
    module Google
      class LoginUserInput < Types::BaseInputObject
        graphql_name "GoogleLoginUserInput"
        description "Log in with Google Oauth"

        argument :code, String, required: true
        argument :state, String, required: false, description: "Required when self-serve is enabled"
        argument :state_secret, String, required: false, description: "Required when self-serve is enabled"
      end
    end
  end
end
