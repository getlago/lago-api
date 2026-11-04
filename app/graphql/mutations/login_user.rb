# frozen_string_literal: true

# Mutations::LoginUser Mutation
module Mutations
  class LoginUser < BaseMutation
    include ThrottlesAuthAttempts

    description "Opens a session for an existing user"

    argument :email, String, required: true
    argument :password, String, required: true

    type Types::Payloads::LoginUserType

    def resolve(email:, password:)
      # The attempt is counted before the password check, so concurrent requests cannot all pass
      # under the limit. A successful login clears the email counters. Requests rejected by the IP
      # limit are not counted against the email.
      # With self-serve on, an unknown email also costs a bcrypt, so IPv6 clients are counted by network.
      ip_rules = Lago::SelfServe.enabled? ? %i[login_per_ip_network login_per_ip_block] : %i[login_per_ip]
      over_ip_limit = ip_rules.map { ::Auth::AttemptsThrottle.hit!(it, client_ip) }.any?
      return too_many_attempts_error if over_ip_limit

      over_email_and_ip_limit = ::Auth::AttemptsThrottle.hit!(:login_per_email_and_ip, email, client_ip)
      over_email_limit = ::Auth::AttemptsThrottle.hit!(:login_per_email, email)
      return too_many_attempts_error if over_email_and_ip_limit || over_email_limit

      result = UsersService.call(:login, email, password)
      return result_error(result) unless result.success?

      ::Auth::AttemptsThrottle.reset!(:login_per_email_and_ip, email, client_ip)
      ::Auth::AttemptsThrottle.reset!(:login_per_email, email)
      result
    end
  end
end
