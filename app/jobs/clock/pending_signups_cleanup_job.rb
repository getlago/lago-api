# frozen_string_literal: true

module Clock
  class PendingSignupsCleanupJob < ClockJob
    unique :until_executed, on_conflict: :log

    BATCH_SIZE = 10_000
    # Kept a week after expiry, so an old link answers "expired" rather than "invalid".
    TOKEN_RETENTION = 7.days

    # On immutable timestamps, so no resend or later write keeps a row alive.
    def perform
      drop_unconfirmable_passwords
      delete_in_batches(PendingSignupToken.where(expires_at: ...TOKEN_RETENTION.ago))
      delete_in_batches(PendingSignup.where(created_at: ...PendingSignup::RETENTION.ago))
    end

    private

    # Links end a day after their attempt's window, then nothing reads its Step 1 password digest, often a real one.
    def drop_unconfirmable_passwords
      now = Time.current

      PendingSignup.where(verified_at: nil, closed_at: nil, expires_at: ...(now - PendingSignupToken::TTL))
        .update_all(password_digest: nil, closed_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    end

    def delete_in_batches(scope)
      loop do
        deleted = scope.model.where(id: scope.limit(BATCH_SIZE).select(:id)).delete_all
        break if deleted < BATCH_SIZE
      end
    end
  end
end
