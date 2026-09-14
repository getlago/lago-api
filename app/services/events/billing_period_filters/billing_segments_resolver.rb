# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    class BillingSegmentsResolver < BaseResolver
      def initialize(billing_segments:, codes: nil, with_last_seen_at: true)
        @billing_segments = billing_segments
        @codes = codes&.to_set || Set.new
        @with_last_seen_at = with_last_seen_at
      end

      def filter_targets
        return {} if target_segments.empty?
        return {} if metric_codes.empty?

        # Aggregate event combinations across all contracts since consolidated invoices
        # can span multiple contracts, each with their own external_subscription_id.
        combinations = contracts.flat_map do |contract|
          event_values_with_history do |**options|
            event_store_for(contract).distinct_codes_and_property_combinations(
              filter_keys: billable_metric_filter_keys, **options
            )
          end
        end

        filter_targets_from_combinations(
          combinations:,
          targets: targets_with_events(combinations.map(&:first).uniq),
          result: recurring_event_filter_targets
        )
      end

      private

      attr_reader :billing_segments, :codes, :with_last_seen_at

      def organization
        @organization ||= target_segments.first.organization
      end

      def filter_target_for(billing_segment)
        Events::BillingPeriodFilters::FilterTarget.from_billing_segment(billing_segment:)
      end

      def target_segments
        @target_segments ||= billing_segments_scope.preload(
          contract_rate_card: {product: [:billable_metric, {filters: {values: :billable_metric_filter}}]}
        ).to_a
      end

      def targets_with_events(codes)
        event_codes = codes.to_set
        target_segments.select { |segment| event_codes.include?(filter_target_for(segment).billable_metric.code) }
      end

      def billing_segments_scope
        scope = BillingSegment.where(id: billing_segments)
          .joins(contract_rate_card: {product: :billable_metric})

        if codes.present?
          scope.where(billable_metrics: {code: codes.to_a})
        else
          scope
        end
      end

      def metric_codes
        @metric_codes ||= codes.presence || billing_segments_scope.distinct.pluck("billable_metrics.code")
      end

      def recurring_metric_codes
        @recurring_metric_codes ||= billing_segments_scope
          .where(billable_metrics: {recurring: true})
          .distinct
          .pluck("billable_metrics.code")
      end

      def current_recurring_targets
        @current_recurring_targets ||= target_segments.select { |segment| filter_target_for(segment).billable_metric.recurring? }
      end

      def period_start
        @period_start ||= target_segments.map(&:started_at).min
      end

      def billable_metric_filter_keys
        @billable_metric_filter_keys ||= billing_segments_scope
          .joins(contract_rate_card: {product: {billable_metric: :filters}})
          .distinct
          .pluck("billable_metric_filters.key")
      end

      def event_store_for(contract)
        @event_stores ||= {}
        @event_stores[contract.id] ||= Events::Stores::StoreFactory.new_instance(
          organization:,
          billing_context: Billing::Context.from(contract:),
          boundaries: {
            from_datetime: period_start,
            to_datetime: target_segments.map(&:ended_at).max
          }
        )
      end

      def contracts
        @contracts ||= target_segments.map(&:contract).uniq
      end
    end
  end
end
