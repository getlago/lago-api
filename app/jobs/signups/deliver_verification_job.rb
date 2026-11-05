# frozen_string_literal: true

module Signups
  class DeliverVerificationJob < ApplicationJob
    queue_as "mailers"

    # Transport errors can pass on a retry. An SMTP 5xx (auth, syntax, fatal) cannot: it goes to the dead set and Sentry.
    retry_on Net::OpenTimeout, Net::ReadTimeout, EOFError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
      LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 6
    # About 4 to 5 h of retries, well inside the 24 h or more a link still has: a relay that stays busy reaches the dead
    # set and Sentry instead of retrying for weeks past the point where the link may no longer be sent.
    retry_on Net::SMTPServerBusy, wait: :polynomially_longer, attempts: 10
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
