# frozen_string_literal: true

module Signups
  class DeliverVerificationJob < ApplicationJob
    queue_as "mailers"

    retry_on Net::OpenTimeout, Net::ReadTimeout, EOFError, LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 6
    retry_on Net::SMTPServerBusy, wait: :polynomially_longer, attempts: 25
    retry_on BaseLockService::FailedToAcquireLock, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    # Only the id: job arguments are logged and kept in Redis.
    def perform(pending_signup_id)
      # Stops queued signup emails as soon as self-serve is turned off or signups are paused.
      return if !Lago::SelfServe.enabled? || Lago::SelfServe.signup_disabled?

      pending_signup = PendingSignup.find_by(id: pending_signup_id)
      DeliverVerificationService.call!(pending_signup:) if pending_signup
    end
  end
end
