# frozen_string_literal: true

module Types
  module Auth
    module Google
      class AcceptInviteInput < Types::BaseInputObject
        graphql_name "GoogleAcceptInviteInput"
        description "Accept a membership invite with Google Oauth"

        argument :code, String, required: true
        argument :invite_token, String, required: true
        argument :state, String, required: false, description: "Required when self-serve is enabled"
        argument :state_secret, String, required: false, description: "Required when self-serve is enabled"
      end
    end
  end
end
