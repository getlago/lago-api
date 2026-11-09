# frozen_string_literal: true

module Mutations
  module Signups
    class Resend < BaseMutation
      include RequiresSelfServeSignup
      include GuardsSignupAttempts

      RETRY_LATER_CODES = %w[resend_too_soon resend_limit_reached].freeze

      graphql_name "ResendSignupEmail"
      description "Sends a new self-serve signup link, which replaces the previous one of the same signup"

      argument :signup_secret, String, required: false
      argument :token, String, required: false, description: "A link of the signup, when its signup secret is not known"
      captcha_token_argument

      field :resend_available_in_seconds, Integer, null: true, description: "Null when this signup cannot send more emails"
      field :resend_limit_reached, Boolean, null: false

      def resolve(signup_secret: nil, token: nil, captcha_token: nil)
        guard_error = signup_guard_error(:resend_signup_email, captcha_token:)
        return guard_error if guard_error

        result = ::Signups::ResendService.call(signup_secret:, token:)

        if result.success?
          {resend_available_in_seconds: result.resend_available_in_seconds, resend_limit_reached: result.resend_limit_reached}
        elsif result.error.is_a?(BaseService::MethodNotAllowedFailure) && RETRY_LATER_CODES.include?(result.error.code)
          too_many_attempts_error(code: result.error.code, details: {retry_after_seconds: result.retry_after_seconds})
        else
          result_error(result)
        end
      end
    end
  end
end
