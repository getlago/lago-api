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
      in_batches_until_done(PendingSignupToken.where(expires_at: ...TOKEN_RETENTION.ago), &:delete_all)
      in_batches_until_done(PendingSignup.where(created_at: ...PendingSignup::RETENTION.ago), &:delete_all)
    end

    private

    # Links end a day after their attempt's window, then nothing reads its Step 1 password digest, often a real one.
    def drop_unconfirmable_passwords
      now = Time.current
      scope = PendingSignup.where(verified_at: nil, closed_at: nil, expires_at: ...(now - PendingSignupToken::TTL))

      in_batches_until_done(scope) { it.update_all(password_digest: nil, closed_at: now, updated_at: now) } # rubocop:disable Rails/SkipsModelValidations
    end

    # Runs the scope again after each batch, so every batch must take its rows out of the scope (deleted or closed).
    def in_batches_until_done(scope)
      loop do
        affected = yield scope.model.where(id: scope.limit(BATCH_SIZE).select(:id))
        break if affected < BATCH_SIZE
      end
    end
  end
end
