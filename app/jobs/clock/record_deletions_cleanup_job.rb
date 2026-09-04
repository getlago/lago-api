# frozen_string_literal: true

module Clock
  class RecordDeletionsCleanupJob < ClockJob
    unique :until_executed, on_conflict: :log

    BATCH_SIZE = 10_000
    RETENTION_PERIOD = 2.months

    def perform
      loop do
        deleted = RecordDeletion.where(
          id: RecordDeletion.where(deleted_at: ...RETENTION_PERIOD.ago).limit(BATCH_SIZE).select(:id)
        ).delete_all

        break if deleted < BATCH_SIZE
      end
    end
  end
end
