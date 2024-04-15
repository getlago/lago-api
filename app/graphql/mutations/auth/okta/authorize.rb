# frozen_string_literal: true

module Mutations
  module Auth
    module Okta
      class Authorize < BaseMutation
        graphql_name 'OktaAuthorize'

        argument :email, String, required: true

        type Types::Auth::Okta::Authorize

        def resolve(email:)
          result = ::Auth::OktaService.new.authorize(email:)
          result.success? ? result : result_error(result)
        end
      end
    end
  end
end
