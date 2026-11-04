# frozen_string_literal: true

module Signups
  # What the tab that started a signup polls with its signup secret. A closed attempt (the address had an account,
  # or got one another way) answers pending until it expires, so the secret never reveals how the address signed up.
  class StatusService < BaseService
    Result = BaseResult[:status, :resend_available_in_seconds, :resend_limit_reached]

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

      # From the attempt's sends and the other emails to its mailbox, so a reloaded "Check your email" screen restores
      # its countdown.
      result.resend_limit_reached = false
      if result.status == :pending
        result.resend_available_in_seconds = pending_signup.resend_available_in_seconds(Time.current)
        result.resend_limit_reached = pending_signup.resend_limit_reached?
      end

      result
    end

    private

    attr_reader :signup_secret
  end
end
