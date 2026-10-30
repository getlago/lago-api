# frozen_string_literal: true

module Clock
  class RetryPendingViesChecksJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 4.hours

    # Every attempt touches the pending check and ViesCheckJob never waits more than
    # MAX_RETRY_DELAY between attempts, so a check untouched for longer has no job left to retry it.
    STALE_AFTER = Customers::ViesCheckJob::MAX_RETRY_DELAY + 1.hour

    def perform
      PendingViesCheck
        .joins(customer: :billing_entity)
        .where(billing_entities: {eu_tax_management: true}, customers: {deleted_at: nil})
        .where(updated_at: ...STALE_AFTER.ago)
        .includes(:customer)
        .find_each do |pending_vies_check|
          Customers::ViesCheckJob.perform_later(pending_vies_check.customer)
        end
    end
  end
end
