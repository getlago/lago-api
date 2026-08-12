# frozen_string_literal: true

module Types
  module Auth
    module EntraId
      class AcceptInviteInput < BaseInputObject
        description "Accept Invite with Entra ID Oauth input arguments"

        argument :code, String, required: true
        argument :invite_token, String, required: true
        argument :state, String, required: true
      end
    end
  end
end
