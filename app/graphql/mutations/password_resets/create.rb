# frozen_string_literal: true

module Mutations
  module PasswordResets
    class Create < BaseMutation
      include ThrottlesAuthAttempts

      graphql_name "CreatePasswordReset"
      description "Creates a new password reset"

      argument :email, String, required: true
      field :id, String, null: false

      # The response, and the work done before it, are the same whether or not the email belongs to a
      # user: the lookup and the reset happen in a job. So the mutation cannot be used to find out which
      # addresses have an account. The id is random and not tied to any record.
      def resolve(email:)
        over_ip_limit = ::Auth::AttemptsThrottle.hit!(:password_reset_per_ip, client_ip)
        over_email_limit = ::Auth::AttemptsThrottle.hit!(:password_reset_per_email, email)
        return too_many_attempts_error if over_ip_limit || over_email_limit

        ::PasswordResets::CreateJob.perform_later(email)

        {id: SecureRandom.uuid}
      end
    end
  end
end
