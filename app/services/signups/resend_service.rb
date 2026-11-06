# frozen_string_literal: true

module Signups
  # Sends a new link for a signup attempt, which replaces its previous one. The attempt is found by its signup secret
  # or one of its links (a replaced or locked one too, within the attempt's 24 h), never by an email address.
  class ResendService < BaseService
    Result = BaseResult[:resend_available_in_seconds, :resend_limit_reached, :retry_after_seconds]

    def initialize(signup_secret: nil, token: nil)
      @signup_secret = signup_secret
      @token = token
      super
    end

    def call
      if signup_secret.blank? && token.blank?
        return result.single_validation_failure!(field: :signup_secret, error_code: "value_is_mandatory")
      end

      token_record = PendingSignupToken.for_token(token) if signup_secret.blank?
      pending_signup = signup_secret.present? ? PendingSignup.for_signup_secret(signup_secret) : token_record&.pending_signup
      return result.not_found_failure!(resource: "pending_signup") unless pending_signup
      # The database history decides, here and under the lock: it holds when the throttling Redis is down, and a
      # Redis counter only knows a worst-case wait.
      return result if refused?(pending_signup, token_record, Time.current)

      sent = Users::EmailLockService.call(email: pending_signup.normalized_email) do
        now = Time.current
        pending_signup.lock!
        token_record&.reload
        next false if refused?(pending_signup, token_record, now)

        pending_signup.record_email_send(now)
        pending_signup.save!
        DeliverVerificationJob.perform_after_commit(pending_signup.id)
        # Counted once the send is committed, so Step 1's Redis check sees it and a refused or failed resend uses none.
        after_commit { count_mailbox_send(pending_signup.mailbox_key) }
        true
      end.value
      return result unless sent

      result.resend_available_in_seconds = pending_signup.resend_available_in_seconds(Time.current)
      result.resend_limit_reached = pending_signup.resend_limit_reached?
      result
    rescue BaseLockService::FailedToAcquireLock
      result.lock_acquisition_failure!(message: "email lock not acquired")
    end

    private

    attr_reader :signup_secret, :token

    # A user that exists for the address another way is not checked: the job then sends "you already have an
    # account", so the answer reveals nothing.
    def refused?(pending_signup, token_record, now)
      if pending_signup.verified? || token_record&.consumed?
        result.not_allowed_failure!(code: "email_already_verified")
      elsif now >= pending_signup.expires_at
        result.not_allowed_failure!(code: "signup_expired")
      elsif pending_signup.resend_limit_reached?
        result.not_allowed_failure!(code: "signup_resend_exhausted")
      else
        refusal, wait = PendingSignup.mailbox_send_state(pending_signup.mailbox_key, now)
        if refusal
          retry_later(pending_signup, now, wait, (refusal == :limit_reached) ? "resend_limit_reached" : "resend_too_soon")
        end
      end

      result.failure?
    end

    def count_mailbox_send(mailbox_key)
      Auth::AttemptsThrottle.hit!(:signup_email_per_minute, mailbox_key)
      Auth::AttemptsThrottle.hit!(:signup_email_per_hour, mailbox_key)
    end

    # A wait that ends after the attempt's window is never followed by a send, as resendAvailableInSeconds says.
    def retry_later(pending_signup, now, wait, code)
      if now + wait < pending_signup.expires_at
        result.retry_after_seconds = wait
        result.not_allowed_failure!(code:)
      else
        result.not_allowed_failure!(code: "signup_resend_exhausted")
      end
    end
  end
end
