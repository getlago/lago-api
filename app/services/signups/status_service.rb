# frozen_string_literal: true

module Signups
  # What the tab that started a signup polls with its signup secret. A closed attempt (the address had an account,
  # or got one another way) answers pending until it expires, so the secret never reveals how the address signed up.
  class StatusService < BaseService
    # pending_signup is set only while pending, for the resend countdown the type computes when it is asked for.
    Result = BaseResult[:status, :pending_signup]

    def initialize(signup_secret:)
      @signup_secret = signup_secret
      super
    end

    def call
      pending_signup = PendingSignup.for_signup_secret(signup_secret)

      result.status = if pending_signup.nil?
        :invalid
      elsif pending_signup.verified?
        :verified
      elsif Time.current >= pending_signup.expires_at + PendingSignupToken::TTL
        :expired
      else
        :pending
      end

      result.pending_signup = pending_signup if result.status == :pending
      result
    end

    private

    attr_reader :signup_secret
  end
end
