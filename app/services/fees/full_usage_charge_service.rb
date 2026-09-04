# frozen_string_literal: true

module Fees
  class FullUsageChargeService < BaseService
    Result = BaseResult[:fees]

    # Summing two windows only reconstructs the lifetime for an aggregation that adds up across
    # them, priced by a charge model where amount(a) + amount(b) == amount(a + b).
    FULL_USAGE_AGGREGATIONS = %w[sum_agg count_agg].freeze

    # Recurring metrics of these types set use_from_boundary to false, so they aggregate all
    # history whatever lower boundary they are given.
    LIFETIME_BY_DEFAULT_AGGREGATIONS = %w[sum_agg unique_count_agg].freeze

    # Both event store bounds are inclusive, so the windows are separated by the finest granularity
    # Postgres stores rather than meeting. ClickHouse stores milliseconds, so nothing falls in it.
    PERIOD_BOUNDARY_GAP = Rational(1, 1_000_000)

    def initialize(invoice:, subscription:, charge:, boundaries:, date_service:, applied_filters:,
      options:, cache:, max_timestamp: nil)
      @invoice = invoice
      @subscription = subscription
      @charge = charge
      @boundaries = boundaries
      @date_service = date_service
      @applied_filters = applied_filters
      @options = options
      @cache = cache
      @max_timestamp = max_timestamp

      super
    end

    def call
      result.fees = if split_across_periods?
        fees_from_both_windows
      else
        fees_for(boundaries, full_usage: !lifetime_by_default?)
      end

      result
    end

    private

    attr_reader :invoice, :subscription, :charge, :boundaries, :date_service, :applied_filters,
      :options, :cache, :max_timestamp

    delegate :billable_metric, to: :charge

    def fees_from_both_windows
      later = fees_for(current_period_boundaries, full_usage: false)
      earlier = fees_for(prior_periods_boundaries, full_usage: false, prior_periods: true)

      Fees::MergePeriodFeesService.call!(earlier_fees: earlier, later_fees: later).fees
    end

    def split_across_periods?
      return false unless cache
      return false if options.calculate_projected_usage || max_timestamp
      return false unless subscription.started_at < date_service.charges_from_datetime

      # A recurring metric ignores the lower boundary, so both windows would aggregate all history
      # and the sum would count every event twice.
      !billable_metric.recurring?
    end

    # The current period entry already holds the whole history, so full usage reads it rather than
    # keeping an entry of its own. Pay in advance is excluded because find_cached_aggregation is
    # scoped by the lower boundary, prorated because the period ratio is applied to it.
    def lifetime_by_default?
      return false if options.calculate_projected_usage || max_timestamp
      return false if charge.pay_in_advance? || charge.prorated?

      billable_metric.recurring? && LIFETIME_BY_DEFAULT_AGGREGATIONS.include?(billable_metric.aggregation_type)
    end

    def fees_for(window, full_usage:, prior_periods: false)
      cache_middleware = Subscriptions::ChargeCacheMiddleware.new(
        subscription:,
        charge:,
        to_datetime: window.charges_to_datetime,
        cache:,
        full_usage:,
        prior_periods:,
        context: (prior_periods_cache_context if prior_periods),
        last_seen_at: applied_filters
      )

      applied_boundaries = window
      applied_boundaries = window.dup.tap { it.max_timestamp = max_timestamp } if max_timestamp

      Fees::ChargeService
        .call!(
          invoice:,
          metered_item: Fees::ChargeService::MeteredItem.from_charge(charge:, boundaries: applied_boundaries),
          subscription:,
          cache_middleware:,
          filtered_aggregations: applied_filters.keys,
          options:
        )
        .fees
    end

    def current_period_boundaries
      @current_period_boundaries ||= BillingPeriodBoundaries.new(
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        issuing_date: date_service.next_end_of_period,
        charges_duration: date_service.charges_duration_in_days,
        timestamp: boundaries.timestamp
      )
    end

    def prior_periods_boundaries
      @prior_periods_boundaries ||= BillingPeriodBoundaries.new(
        from_datetime: subscription.started_at,
        to_datetime: prior_periods_to_datetime,
        charges_from_datetime: subscription.started_at,
        charges_to_datetime: prior_periods_to_datetime,
        issuing_date: date_service.next_end_of_period,
        charges_duration: date_service.charges_duration_in_days,
        timestamp: boundaries.timestamp
      )
    end

    def prior_periods_to_datetime
      @prior_periods_to_datetime ||= date_service.charges_from_datetime - PERIOD_BOUNDARY_GAP
    end

    # None of these appear in the cache key, and no billing boundary expires this entry, so a change
    # to any of them has to be caught on read.
    def prior_periods_cache_context
      @prior_periods_cache_context ||= [
        subscription.started_at.iso8601(6),
        prior_periods_to_datetime.iso8601(6),
        billable_metric.updated_at.iso8601(6),
        subscription.plan.interval,
        subscription.customer.applicable_timezone
      ].join("|")
    end
  end
end
