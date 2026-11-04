# frozen_string_literal: true

module Resolvers
  module Signups
    class VerificationResolver < Resolvers::BaseResolver
      include RequiresSelfServe
      include GuardsSignupAttempts

      description "Reads the state of a self-serve signup verification link without confirming it"

      argument :signup_secret, String, required: false
      argument :token, String, required: true

      type Types::Signups::VerificationObject, null: false

      def resolve(token:, signup_secret: nil)
        guard_error = signup_guard_error(:signup_verification)
        return guard_error if guard_error

        result = ::Signups::TokenStatusService.call(token:, signup_secret:)
        {status: result.status.to_s, email: result.email, password_required: result.password_required}
      end
    end
  end
end
