# frozen_string_literal: true

module Resolvers
  module Signups
    # Lets the signup form check an address when the field loses focus, with the server's lists. It never looks
    # users up, so it reveals nothing about accounts.
    class EmailCheckResolver < Resolvers::BaseResolver
      include RequiresSelfServe
      include GuardsSignupAttempts

      description "Checks the format and the company domain of a self-serve signup email"

      argument :email, String, required: true

      type Types::Signups::EmailCheckObject, null: false

      def resolve(email:)
        guard_error = signup_guard_error(:signup_email_check)
        return guard_error if guard_error

        validation = ::Signups::ValidateEmailService.call(email:)
        {valid: validation.success?, code: validation.error&.messages&.dig(:email)&.first}
      end
    end
  end
end
