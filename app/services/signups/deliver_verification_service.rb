# frozen_string_literal: true

module Signups
  # Sends the email of a signup attempt: its verification link, or "you already have an account" when the address
  # has a user. Decided here, off the request, so the request that asked for it reveals nothing.
  class DeliverVerificationService < BaseService
    Result = BaseResult

    def initialize(pending_signup:)
      @pending_signup = pending_signup
      super
    end

    def call
      mail = Users::EmailLockService.call(email: pending_signup.normalized_email) do
        pending_signup.lock!
        prepare_mail
      end.value

      # After commit: SMTP never holds the lock, and the mail was rendered (and its token issued) under it.
      mail&.deliver_now
      result
    end

    private

    attr_reader :pending_signup

    def prepare_mail
      if pending_signup.verified?
        # Its own link created the user meanwhile: nothing to send.
        nil
      elsif User.where("LOWER(email) = ?", pending_signup.normalized_email).exists?
        # The password typed at Step 1 is often the person's real one: keep no copy of it.
        pending_signup.update!(password_digest: nil, closed_at: pending_signup.closed_at || Time.current)
        SignupMailer.with(pending_signup:).account_exists
      elsif !pending_signup.closed? && link_alive?
        SignupMailer.with(pending_signup:).verification.tap(&:message)
      end
    end

    # A link ends a day after the attempt's window, so a delivery retried later would carry a dead one.
    def link_alive?
      Time.current < pending_signup.expires_at + PendingSignupToken::TTL
    end
  end
end
