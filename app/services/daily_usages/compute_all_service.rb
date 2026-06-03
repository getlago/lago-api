# frozen_string_literal: true

module DailyUsages
  class ComputeAllService < BaseService
    def initialize(timestamp: Time.current)
      @timestamp = timestamp

      super
    end

    def call
      each_subscription do |subscription|
        schedule_daily_usage(subscription)
      end

      result
    end

    private

    attr_reader :timestamp

    def schedule_daily_usage(subscription)
      DailyUsages::ComputeJob.set(wait: job_wait_time).perform_later(subscription, timestamp:)
    end

    def job_wait_time
      # Randomize job wait time to distribute load across the system.
      # This prevents thundering herd effect when processing large batches,
      # and helps interleave jobs from different organizations since subscriptions
      # within the same organization usually have very similar load profiles.
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

    def each_organization(&block)
      Organization.with_revenue_analytics_support.find_each(&block)
    end

    def each_billing_entity(organization, &block)
      organization.billing_entities.unscope(:order).find_each(&block)
    end

    def each_customer_batch(billing_entity, &block)
      Customer.joins(:billing_entity)
        .where(billing_entity_id: billing_entity.id)
        .where("DATE_PART('hour', (:timestamp#{at_time_zone})) IN (0, 1, 2)", timestamp:)
        .in_batches(&block)
    end

    def each_subscription(&block)
      each_organization do |organization|
        each_billing_entity(organization) do |billing_entity|
          each_customer_batch(billing_entity) do |customers|
            customer_ids = customers.select(:id)
            subscription_ids_with_daily_usage = DailyUsage.usage_date_in_timezone(timestamp.to_date - 1.day)
              .where(customer_id: customer_ids)
              .select(:subscription_id)
            Subscription.where(customer_id: customer_ids)
              .active
              .where.not(id: subscription_ids_with_daily_usage)
              .where(skip_daily_usage: false)
              .where(
                "last_received_event_on >= :yesterday OR #{PLAN_HAS_TIME_DEPENDENT_CHARGE_SQL}",
                yesterday: timestamp.to_date - 1.day
              )
              .find_each do |subscription|
                yield subscription
            end
          end
        end
      end
    end

    # Subscriptions whose usage can change between billing boundaries even without receiving new
    # events: prorated charges, recurring billable metrics, and weighted_sum aggregations (which
    # are time-weighted). These must be recomputed every day regardless of `last_received_event_on`,
    # otherwise their daily usage would go stale until the next event arrives.
    #
    # NOTE: fixed charges are intentionally excluded — they are not part of the metered daily usage
    # (`CustomerUsageService` only computes usage charges), so a prorated fixed charge does not
    # change the daily usage value.
    PLAN_HAS_TIME_DEPENDENT_CHARGE_SQL = <<~SQL.squish.freeze
      EXISTS (
        SELECT 1
        FROM charges
        JOIN billable_metrics ON billable_metrics.id = charges.billable_metric_id
        WHERE charges.plan_id = subscriptions.plan_id
          AND charges.deleted_at IS NULL
          AND billable_metrics.deleted_at IS NULL
          AND (
            charges.prorated = TRUE
            OR billable_metrics.recurring = TRUE
            OR billable_metrics.aggregation_type = #{BillableMetric.aggregation_types[:weighted_sum_agg]}
          )
      )
    SQL
  end
end
