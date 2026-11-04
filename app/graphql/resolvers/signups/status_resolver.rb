# frozen_string_literal: true

module Resolvers
  module Signups
    class StatusResolver < Resolvers::BaseResolver
      include RequiresSelfServe
      include GuardsSignupAttempts

      description "Tells the tab that started a self-serve signup whether its email was confirmed"

      argument :signup_secret, String, required: true

      type Types::Signups::StatusObject, null: false

      def resolve(signup_secret:)
        guard_error = signup_guard_error(:signup_status)
        return guard_error if guard_error

        result = ::Signups::StatusService.call(signup_secret:)
        {
          status: result.status.to_s,
          resend_available_in_seconds: result.resend_available_in_seconds,
          resend_limit_reached: result.resend_limit_reached
        }
      end
    end
  end
end
