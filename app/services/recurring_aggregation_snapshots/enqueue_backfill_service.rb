# frozen_string_literal: true

require "sidekiq/api"

module RecurringAggregationSnapshots
  class EnqueueBackfillService < BaseService
    Result = BaseResult[:subscription_ids, :contract_ids]

    BATCH_SIZE = 100
    MAX_QUEUE_SIZE = 1_000
    POLL_INTERVAL = 5

    # subscription_ids, contract_ids: the owners to backfill among the backfillable ones, all of them when nil
    def initialize(organization:, subscription_ids: nil, contract_ids: nil, batch_size: BATCH_SIZE, max_queue_size: MAX_QUEUE_SIZE, poll_interval: POLL_INTERVAL)
      @organization = organization
      @subscription_ids = subscription_ids
      @contract_ids = contract_ids
      @batch_size = batch_size
      @max_queue_size = max_queue_size
      @poll_interval = poll_interval

      super
    end

    def call
      result.subscription_ids = enqueue(owners_to_backfill(BackfillService.backfillable_subscriptions(organization), subscription_ids))
      result.contract_ids = enqueue(owners_to_backfill(ContractBackfillService.backfillable_contracts(organization), contract_ids))
      result
    end

    private

    attr_reader :organization, :subscription_ids, :contract_ids, :batch_size, :max_queue_size, :poll_interval

    def owners_to_backfill(owners, ids)
      ids ? owners.where(id: ids) : owners
    end

    def enqueue(owners)
      owners.find_in_batches(batch_size:).flat_map do |batch|
        wait_for_room
        # A job still queued, or one that died, holds its unique lock until it expires: no second job then
        batch.select { BackfillJob.perform_later(it) }.map(&:id)
      end
    end

    # The whole queue, as low_priority is shared with the other background work
    def wait_for_room
      queue = Sidekiq::Queue.new(BackfillJob.queue_name)
      sleep(poll_interval) while queue.size > max_queue_size
    end
  end
end
