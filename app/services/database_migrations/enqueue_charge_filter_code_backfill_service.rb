# frozen_string_literal: true

require "sidekiq/api"

module DatabaseMigrations
  class EnqueueChargeFilterCodeBackfillService < BaseService
    Result = BaseResult

    BATCH_SIZE = 100
    MAX_QUEUE_SIZE = 1_000
    POLL_INTERVAL = 5

    def initialize(batch_size: BATCH_SIZE, max_queue_size: MAX_QUEUE_SIZE, poll_interval: POLL_INTERVAL)
      @batch_size = batch_size
      @max_queue_size = max_queue_size
      @poll_interval = poll_interval

      super
    end

    def call
      billing_organization_ids.each { enqueue_charges_of(it) }

      result
    end

    private

    attr_reader :batch_size, :max_queue_size, :poll_interval

    # One organization at a time, each with its own cursor, rather than one walk over every charge
    # with the organizations as an `IN` list: that list is as long as the number of organizations
    # billing anything and would be repeated in every batch query.
    def enqueue_charges_of(organization_id)
      cursor = nil

      loop do
        wait_for_room

        charge_ids = next_charge_ids(organization_id, cursor)
        break if charge_ids.empty?

        cursor = charge_ids.last

        charge_ids.each { BackfillChargeFilterCodesJob.perform_later(it) }
      end
    end

    def wait_for_room
      sleep(poll_interval) while queue.size > max_queue_size
    end

    # The whole queue, not just this job's share of it — the overrides pass lands here too, and so
    # does everything else on low_priority. Burying that is what the limit exists to prevent.
    def queue
      Sidekiq::Queue.new(BackfillChargeFilterCodesJob.queue_name)
    end

    # Both conditions, as the job checks again before it writes. `charges.parent_id` goes back to
    # NULL when the parent charge is deleted (has_many :children, dependent: :nullify), so on its
    # own it cannot tell a plan's own charge from an override that lost its parent
    def next_charge_ids(organization_id, cursor)
      pending = ChargeFilter.unscope(:order)
        .where(code: nil)
        .where("charge_filters.charge_id = charges.id")

      scope = Charge.kept
        .joins(:plan)
        .where(parent_id: nil, organization_id:)
        .where(plans: {parent_id: nil, deleted_at: nil})
        .where(pending.arel.exists)
        .order(:id)
        .limit(batch_size)

      scope = scope.where("charges.id > ?", cursor) if cursor

      scope.pluck(:id)
    end

    # An organization with nothing active or pending should be skipped.
    def billing_organization_ids
      Subscription.where(status: %i[active pending]).distinct.pluck(:organization_id)
    end
  end
end
