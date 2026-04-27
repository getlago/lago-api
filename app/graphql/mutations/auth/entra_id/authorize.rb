# frozen_string_literal: true

module Mutations
  module Auth
    module EntraId
      class Authorize < BaseMutation
        graphql_name "EntraIdAuthorize"

        argument :email, String, required: true
        argument :invite_token, String, required: false

        type Types::Auth::EntraId::Authorize

        def resolve(email:, invite_token: nil)
          result = ::Auth::EntraId::AuthorizeService.call(email:, invite_token:)
          result.success? ? result : result_error(result)
        end
      end
    end
  end
end
