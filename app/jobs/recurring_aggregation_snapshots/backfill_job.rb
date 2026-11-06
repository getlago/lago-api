# frozen_string_literal: true

module RecurringAggregationSnapshots
  class BackfillJob < ApplicationJob
    class ChargesFailedError < StandardError; end

    queue_as :low_priority

    unique :until_executed, on_conflict: :log

    # A rerun replaces the snapshots of every charge, so retrying the subscription is safe
    retry_on ChargesFailedError, wait: :polynomially_longer, attempts: 3

    def perform(subscription)
      result = BackfillService.call(subscription:)
      # Terminated since it was enqueued: its snapshots are no longer read
      return if result.failure? && result.error.code == "subscription_not_active"

      result.raise_if_error!
      return if result.failed_charges.empty?

      raise ChargesFailedError, "Charges #{result.failed_charges.map(&:id).join(", ")} failed to backfill"
    end
  end
end
