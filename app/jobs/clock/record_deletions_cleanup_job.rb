# frozen_string_literal: true

module Clock
  class RecordDeletionsCleanupJob < ClockJob
    unique :until_executed, on_conflict: :log

    class_attribute :batch_size, default: 10_000 # rubocop:disable ThreadSafety/ClassAndModuleAttributes
    class_attribute :retention_period, default: 6.months # rubocop:disable ThreadSafety/ClassAndModuleAttributes

    # NOTE: A tombstone only has to survive long enough for the data pipeline to sync it
    #   once. The window is far longer than that so a consumer reconciling its own copy
    #   months later, or a full refresh of its dataset, still sees the deletion.
    #
    # NOTE: Manual batching rather than `in_batches` so the delete stays on the
    #   `deleted_at` index instead of being reordered by id.
    def perform
      loop do
        deleted = RecordDeletion.where(
          id: RecordDeletion.where(deleted_at: ...retention_period.ago).limit(batch_size).select(:id)
        ).delete_all

        break if deleted < batch_size
      end
    end
  end
end
