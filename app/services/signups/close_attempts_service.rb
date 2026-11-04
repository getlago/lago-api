# frozen_string_literal: true

module Signups
  # Ends an address's open signup attempts once it has a user (links stop, digests are dropped), never marking them
  # verified, so no signup secret becomes a session. Callers hold Users::EmailLockService for the address.
  class CloseAttemptsService < BaseService
    Result = BaseResult

    def initialize(normalized_email:, except: nil)
      @normalized_email = normalized_email
      @except = except
      super
    end

    def call
      now = Time.current
      attempts = PendingSignup.where(normalized_email:, verified_at: nil, closed_at: nil)
      attempts = attempts.where.not(id: except.id) if except

      PendingSignupToken.pending.where(pending_signup_id: attempts.select(:id)).update_all(status: "replaced", updated_at: now) # rubocop:disable Rails/SkipsModelValidations
      attempts.update_all(password_digest: nil, closed_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations

      result
    end

    private

    attr_reader :normalized_email, :except
  end
end
