# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Mutations
  module Auth
    module Okta
      class Login < BaseMutation
        graphql_name "OktaLogin"

        argument :code, String, required: true
        argument :state, String, required: true

        type Types::Payloads::LoginUserType

        def resolve(code:, state:)
          result = ::Auth::Okta::LoginService.call(code:, state:)
          result.success? ? result : result_error(result)
        end
      end
    end
  end
end
