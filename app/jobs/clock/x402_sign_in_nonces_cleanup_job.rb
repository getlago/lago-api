# frozen_string_literal: true

module Clock
  class X402SignInNoncesCleanupJob < ClockJob
    unique :until_executed, on_conflict: :log

    BATCH_SIZE = 10_000
    RETENTION_PERIOD = 1.day

    def perform
      loop do
        deleted = X402::SignInNonce.where(
          id: X402::SignInNonce.where(created_at: ...RETENTION_PERIOD.ago).limit(BATCH_SIZE).select(:id)
        ).delete_all

        break if deleted < BATCH_SIZE
      end
    end
  end
end
