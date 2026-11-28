# frozen_string_literal: true

module DailyUsages
  class ComputeAllService < BaseService
    ENQUEUE_BATCH_SIZE = 1_000

    Result = BaseResult

    def initialize(timestamp: Time.current)
      @timestamp = timestamp

      super
    end

    def call
      Organization.with_revenue_analytics_support.find_each do |organization|
        schedule_organization(organization)
      rescue => e
        # Nothing recomputes an older day and the clock job is not retried, so letting one
        # organization's failure abort the run would permanently lose the day for all the others.
        report_failure(organization, e)
      end

      result
    end

    private

    attr_reader :timestamp

    def schedule_organization(organization)
      ids = Set.new

      # Each leg runs its (cheap, indexed) selection query ONCE via pluck. We never iterate the
      # heavy relation with find_each, which would re-execute the whole query per 1000-row batch.
      ids.merge(event_subscriptions(organization).pluck("subscriptions.id"))
      ids.merge(time_dependent_subscriptions(organization).pluck("subscriptions.id"))
      ids.merge(recurring_rollover_subscriptions(organization).pluck("subscriptions.id"))

      # Drop subscriptions already computed for yesterday. Subtracting here runs the dedup query
      # once per organization, instead of three times (once per leg) if it lived in base_scope.
      ids.subtract(already_computed_subscription_ids(organization)) if ids.any?

      enqueue(Subscription, DailyUsages::ComputeJob, ids)

      contract_ids = metered_contracts(organization).pluck("contracts.id").to_set
      contract_ids.subtract(already_computed_contract_ids(organization)) if contract_ids.any?

      enqueue(Contract, DailyUsages::ComputeContractJob, contract_ids)
    end

    def report_failure(organization, error)
      context = {organization_id: organization.id, timestamp: timestamp.iso8601}

      Rails.logger.warn(
        "Daily usage computation skipped for an organization: #{error.class} #{error.message} " \
        "#{context.map { |k, v| "#{k}=#{v}" }.join(" ")}"
      )
      Sentry.capture_exception(error, extra: context)
    end

    # Recompute every day for subscriptions that received an event recently: their usage may have
    # changed. Restricted to customers entering a new day in their timezone.
    #
    # last_received_event_on is a date in the customer's timezone, so it is compared with their
    # local yesterday. The UTC yesterday is never after it in the window: it only serves the index.
    def event_subscriptions(organization)
      base_scope(organization)
        .joins(customer: :billing_entity)
        .where(timezone_window_sql, timestamp:)
        .where("subscriptions.last_received_event_on >= :yesterday", yesterday: yesterday)
        .where("subscriptions.last_received_event_on >= #{local_yesterday_sql}", timestamp:)
    end

    # Recompute every day for subscriptions whose usage changes between billing boundaries WITHOUT
    # new events (prorated charges, weighted_sum aggregations), even when no event was received.
    #
    # We resolve the time-dependent plan ids as a subquery and let Postgres hash semi-join, instead
    # of a correlated EXISTS (which is evaluated per row and is catastrophic on plan-per-subscription
    # organizations).
    def time_dependent_subscriptions(organization)
      base_scope(organization)
        .where(plan_id: time_dependent_plan_ids(organization))
        .joins(customer: :billing_entity)
        .where(timezone_window_sql, timestamp:)
        .where(no_recent_event_sql, timestamp:)
    end

    # Recurring metrics are constant between events, so they only need to be recomputed once per
    # period, to capture the carried-over value of the new period.
    #
    # `ComputeService` skips the billing day itself (its usage comes from the periodic invoice), so
    # the carry-over row (usage_date = period start) is created on the run of the *next* day. We
    # therefore select subscriptions whose period rolled over on the local yesterday. For customers
    # in the window, `timestamp - 12.hours` falls in its middle, even after a 23-hour DST day.
    def recurring_rollover_subscriptions(organization)
      scope = base_scope(organization).where(plan_id: recurring_plan_ids(organization))

      # The query joins the customer and its billing entity, which the timezone conditions read.
      Subscriptions::BillingDateQuery.call(subscriptions: scope, timestamp: timestamp - 12.hours)
        .subscriptions
        .where(timezone_window_sql, timestamp:)
        .where(no_recent_event_sql, timestamp:)
    end

    def base_scope(organization)
      Subscription.where(organization_id: organization.id)
        .active
        .where(skip_daily_usage: false)
    end

    # Plans with a charge whose usage changes daily without events: prorated charges or weighted_sum
    # aggregations. Returned as a relation so it composes as a subquery (semi-join).
    #
    # NOTE: fixed charges are intentionally excluded — `CustomerUsageService` only computes usage
    # charges, so a prorated fixed charge does not change the daily usage value.
    def time_dependent_plan_ids(organization)
      Charge.joins(:plan, :billable_metric)
        .where(plans: {organization_id: organization.id})
        .where(charges: {deleted_at: nil}, billable_metrics: {deleted_at: nil})
        .where(
          "charges.prorated = TRUE OR billable_metrics.aggregation_type = ?",
          BillableMetric.aggregation_types[:weighted_sum_agg]
        )
        .select("charges.plan_id")
    end

    # Plans with a recurring billable metric. Returned as a relation so it composes as a subquery.
    def recurring_plan_ids(organization)
      Charge.joins(:plan, :billable_metric)
        .where(plans: {organization_id: organization.id})
        .where(charges: {deleted_at: nil}, billable_metrics: {deleted_at: nil, recurring: true})
        .select("charges.plan_id")
    end

    # Contracts have no last received event to select on: every active contract with a metered
    # card is computed once a day, in the window its customer enters a new day. A contract
    # terminated since the previous run is kept for its last day, which ComputeContractService
    # skips when the termination came before it.
    def metered_contracts(organization)
      Contract.where(organization_id: organization.id)
        .where(
          "contracts.status = :active OR (contracts.status = :terminated AND contracts.terminated_at >= :since)",
          active: Contract::STATUSES[:active], terminated: Contract::STATUSES[:terminated], since: timestamp - 2.days
        )
        .where(id: metered_contract_ids(organization))
        .joins(customer: :billing_entity)
        .where(timezone_window_sql, timestamp:)
    end

    # Returned as a relation so it composes as a subquery.
    def metered_contract_ids(organization)
      ContractRateCard.where(organization_id: organization.id)
        .priced
        .joins(rate_card: :product)
        .where(products: {product_type: Product::PRODUCT_TYPES[:metered]})
        .select(:contract_id)
    end

    # Load the matched records by primary key (cheap, indexed) and enqueue, in bounded slices
    # so we never hold more than ENQUEUE_BATCH_SIZE records in memory at once.
    def enqueue(model, job, ids)
      ids.each_slice(ENQUEUE_BATCH_SIZE) do |batch|
        # rubocop:disable Rails/FindEach -- each_slice already bounds the batch to ENQUEUE_BATCH_SIZE;
        # find_each would add redundant keyset batching on top of an already-small `id IN (...)` query.
        model.where(id: batch).each do |record|
          job.set(wait: job_wait_time).perform_later(record, timestamp:)
        end
        # rubocop:enable Rails/FindEach
      end
    end

    def already_computed_subscription_ids(organization)
      computed_yesterday(organization).where.not(subscription_id: nil).pluck(:subscription_id)
    end

    def already_computed_contract_ids(organization)
      computed_yesterday(organization).where.not(contract_id: nil).distinct.pluck(:contract_id)
    end

    # Daily usages of each customer's local yesterday, the usage_date the compute services write.
    # Only ids the windowed legs selected are subtracted, and for their customers that date is the
    # UTC date or the day before, hence the indexed range. A window condition here would make
    # Postgres, which cannot estimate it, read the whole history of every customer in the window.
    def computed_yesterday(organization)
      DailyUsage
        .where(organization_id: organization.id)
        .where(usage_date: yesterday..timestamp.to_date)
        .joins(customer: :billing_entity)
        .where("daily_usages.usage_date = #{local_yesterday_sql}", timestamp:)
    end

    # The UTC yesterday: for a customer entering a new day, their local yesterday or the day before.
    def yesterday
      @yesterday ||= timestamp.to_date - 1.day
    end

    def local_yesterday_sql
      "DATE(:timestamp#{at_time_zone}) - 1"
    end

    def no_recent_event_sql
      "subscriptions.last_received_event_on IS NULL OR subscriptions.last_received_event_on < #{local_yesterday_sql}"
    end

    # Only schedule customers entering a new day in their timezone; the hourly clock catches each
    # timezone as it crosses midnight.
    def timezone_window_sql
      "DATE_PART('hour', (:timestamp#{at_time_zone})) IN (0, 1, 2)"
    end

    def job_wait_time
      # Randomize job wait time to distribute load across the system. This prevents a thundering
      # herd, and interleaves jobs from different organizations (subscriptions within an org usually
      # share a load profile).
      rand(scheduling_interval)
    end

    def scheduling_interval
      @scheduling_interval ||= begin
        raw_value = ENV["LAGO_DAILY_USAGE_SCHEDULING_JITTER_SECONDS"]
        parsed = Integer(raw_value, exception: false) if raw_value
        parsed = nil if parsed && parsed <= 0
        (parsed || 30.minutes).to_i
      end
    end
  end
end
