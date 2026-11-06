# frozen_string_literal: true

module DatabaseMigrations
  # Every progressive billing invoice issued before invoices.progressive_billing_trigger existed was
  # triggered by usage thresholds, and has applied usage thresholds.
  class BackfillProgressiveBillingTriggerJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    # ApplicationJob sets retry: 0. The chain is self-terminating, so one failed batch
    # would silently end the whole backfill.
    sidekiq_options retry: 5

    BATCH_SIZE = 1_000

    def perform(cursor = nil)
      invoice_ids = next_invoice_ids(cursor)

      Invoice.where(id: invoice_ids, progressive_billing_trigger: nil)
        .update_all(progressive_billing_trigger: "usage_threshold", updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      if invoice_ids.size == BATCH_SIZE
        self.class.perform_later(invoice_ids.last)
      else
        Rails.logger.info("Finished backfilling invoices.progressive_billing_trigger")
      end
    end

    def lock_key_arguments
      [arguments]
    end

    private

    def next_invoice_ids(cursor)
      scope = AppliedUsageThreshold.distinct.order(:invoice_id).limit(BATCH_SIZE)
      scope = scope.where("applied_usage_thresholds.invoice_id > ?", cursor) if cursor

      scope.pluck(:invoice_id)
    end
  end
end
