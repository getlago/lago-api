# frozen_string_literal: true

require "sidekiq/api"

module RecurringAggregationSnapshots
  class EnqueueBackfillService < BaseService
    Result = BaseResult[:subscription_ids]

    BATCH_SIZE = 100
    MAX_QUEUE_SIZE = 1_000
    POLL_INTERVAL = 5

    def initialize(organization:, subscription_ids: nil, batch_size: BATCH_SIZE, max_queue_size: MAX_QUEUE_SIZE, poll_interval: POLL_INTERVAL)
      @organization = organization
      @subscription_ids = subscription_ids
      @batch_size = batch_size
      @max_queue_size = max_queue_size
      @poll_interval = poll_interval

      super
    end

    def call
      result.subscription_ids = []

      subscriptions_to_backfill.find_in_batches(batch_size:) do |subscriptions|
        wait_for_room
        # A job still queued, or one that died, holds its unique lock until it expires: no second job then
        enqueued = subscriptions.select { BackfillJob.perform_later(it) }
        result.subscription_ids.concat(enqueued.map(&:id))
      end

      result
    end

    private

    attr_reader :organization, :subscription_ids, :batch_size, :max_queue_size, :poll_interval

    def subscriptions_to_backfill
      subscriptions = BackfillService.backfillable_subscriptions(organization)
      subscription_ids ? subscriptions.where(id: subscription_ids) : subscriptions
    end

    # The whole queue, as low_priority is shared with the other background work
    def wait_for_room
      queue = Sidekiq::Queue.new(BackfillJob.queue_name)
      sleep(poll_interval) while queue.size > max_queue_size
    end
  end
end
