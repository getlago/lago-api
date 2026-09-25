# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    class ChargesResolver < BaseResolver
      def initialize(subscription:, boundaries:, codes: nil, with_last_seen_at: true, precomputed_filters: {})
        @subscription = subscription
        @boundaries = boundaries
        @codes = codes
        @with_last_seen_at = with_last_seen_at
        @precomputed_filters = precomputed_filters
      end

      private

      attr_reader :subscription, :boundaries, :codes, :with_last_seen_at, :precomputed_filters

      delegate :organization, :plan, to: :subscription

      def period_start
        boundaries.charges_from_datetime
      end

      def event_store
        @event_store ||= Events::Stores::StoreFactory.new_instance(
          organization: organization,
          billing_context: Billing::Context.from(subscription:),
          boundaries: {
            from_datetime: boundaries.charges_from_datetime,
            to_datetime: boundaries.charges_to_datetime
          }
        )
      end

      def record_precomputed_targets(result)
        precomputed_filters.each do |charge, filter_ids|
          target_key = filter_target_for(charge).target_key

          # No ingestion timestamp: the charge cache is bypassed for a precomputed pricing bucket,
          # so nothing compares against it.
          filter_ids.each { record(result, target_key, it, nil) }
        end
      end

      # A code outside of the plan matches no event, so codes is used as is: dropping it would leave
      # its charge out of the result, billed as zero units instead of surfaced.
      def metric_codes(record_id: nil)
        @metric_codes ||= scoped_codes - precomputed_only_codes
      end

      def scoped_codes
        @scoped_codes ||= codes || plan.billable_metrics.distinct.pluck(:code)
      end

      # A code is dropped only when every charge carrying it is served from the buckets: shared with
      # a charge the buckets cannot answer, it still has to be resolved from the events store.
      def precomputed_only_codes
        return [] if precomputed_filters.empty?

        precomputed_filters.keys.map { it.billable_metric.code }.uniq - delegated_codes
      end

      def delegated_codes
        @delegated_codes ||= plan.charges
          .joins(:billable_metric)
          .where(billable_metrics: {code: scoped_codes})
          .where.not(id: precomputed_charge_ids)
          .distinct
          .pluck("billable_metrics.code")
      end

      def precomputed_charge_ids
        @precomputed_charge_ids ||= precomputed_filters.keys.map(&:id)
      end

      def filter_target_for(charge)
        @filter_targets ||= {}.compare_by_identity
        @filter_targets[charge] ||= Events::BillingPeriodFilters::FilterTarget.from_charge(charge:)
      end

      def targets_with_events(codes)
        targets = plan.charges
          .joins(:billable_metric)
          .where(billable_metrics: {code: codes})
          .includes(billable_metric: :filters, filters: {values: :billable_metric_filter})
        return targets if precomputed_filters.empty?

        # A served charge sharing its code with a delegated one is in the queried codes but takes
        # its filters from the buckets, so the combinations must not reach it.
        targets.where.not(id: precomputed_charge_ids)
      end

      def billable_metric_filter_keys
        @billable_metric_filter_keys ||= BillableMetricFilter
          .where(billable_metric_id: plan.billable_metrics.where(code: metric_codes).select(:id))
          .distinct
          .pluck(:key)
      end

      def recurring_metric_codes
        @recurring_metric_codes ||= plan.billable_metrics.where(recurring: true).where(code: metric_codes).distinct.pluck(:code)
      end

      def current_recurring_targets
        @current_recurring_targets ||= plan.charges
          .joins(:billable_metric)
          .where(billable_metrics: {recurring: true})
          .includes(:filters)
          .to_a
      end
    end
  end
end
