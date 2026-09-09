# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    class ChargesResolver < BaseResolver
      def initialize(subscription:, boundaries:, codes: nil, with_last_seen_at: true)
        @subscription = subscription
        @boundaries = boundaries
        @codes = codes
        @with_last_seen_at = with_last_seen_at
      end

      private

      attr_reader :subscription, :boundaries, :codes, :with_last_seen_at

      delegate :organization, :plan, to: :subscription

      def period_start
        boundaries.charges_from_datetime
      end

      def event_store
        @event_store ||= Events::Stores::StoreFactory.new_instance(
          organization: organization,
          context: Events::Stores::EventContext.from(subscription:),
          boundaries: {
            from_datetime: boundaries.charges_from_datetime,
            to_datetime: boundaries.charges_to_datetime
          }
        )
      end

      # A code outside of the plan matches no event, so codes is used as is: dropping it would leave
      # its charge out of the result, billed as zero units instead of surfaced.
      def metric_codes
        @metric_codes ||= codes || plan.billable_metrics.distinct.pluck(:code)
      end

      def filter_target_for(charge)
        Events::BillingPeriodFilters::FilterTarget.from_charge(charge:)
      end

      def targets_with_events(codes)
        plan.charges
          .joins(:billable_metric)
          .where(billable_metrics: {code: codes})
          .includes(billable_metric: :filters, filters: {values: :billable_metric_filter})
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
