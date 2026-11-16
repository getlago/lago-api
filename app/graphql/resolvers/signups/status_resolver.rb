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
        {status: result.status.to_s, pending_signup: result.pending_signup}
      end
    end
  end
end
