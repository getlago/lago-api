# frozen_string_literal: true

module RecurringAggregationSnapshots
  class BackfillJob < ApplicationJob
    class ChargesFailedError < StandardError; end

    queue_as :low_priority

    unique :until_executed, on_conflict: :log

    # A rerun replaces the snapshots of every charge or rate card, so retrying the owner is safe
    retry_on ChargesFailedError, wait: :polynomially_longer, attempts: 3

    # owner: a subscription, or a contract
    def perform(owner)
      contract = owner.is_a?(Contract)
      result = contract ? ContractBackfillService.call(contract: owner) : BackfillService.call(subscription: owner)

      # Terminated since it was enqueued: its snapshots are no longer read
      return if result.failure? && result.error.code.in?(%w[subscription_not_active contract_not_active])

      result.raise_if_error!
      failed = contract ? result.failed_rate_cards : result.failed_charges
      return if failed.empty?

      raise ChargesFailedError, "#{contract ? "Rate cards" : "Charges"} #{failed.map(&:id).join(", ")} failed to backfill"
    end
  end
end
