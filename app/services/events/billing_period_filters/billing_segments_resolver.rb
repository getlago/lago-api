# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    class BillingSegmentsResolver < BaseResolver
      def initialize(contract:, billing_segments:, codes: nil, with_last_seen_at: true)
        @contract = contract
        @billing_segments = billing_segments
        @codes = codes&.to_set || Set.new
        @with_last_seen_at = with_last_seen_at
      end

      def filter_targets
        return {} if target_segments.empty?
        return {} if metric_codes.empty?

        combinations = event_store.distinct_codes_and_property_combinations(
          codes: metric_codes,
          filter_keys: billable_metric_filter_keys,
          with_last_seen_at:
        )

        filter_targets_from_combinations(combinations:, targets: target_segments)
      end

      private

      attr_reader :contract, :billing_segments, :codes, :with_last_seen_at

      delegate :organization, to: :contract

      def filter_target_for(billing_segment)
        Events::BillingPeriodFilters::FilterTarget.from_billing_segment(billing_segment:)
      end

      def target_segments
        @target_segments ||= billing_segments_scope.preload(
          contract_rate_card: {product: [:billable_metric, {filters: {values: :billable_metric_filter}}]}
        ).to_a
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

      def billable_metric_filter_keys
        @billable_metric_filter_keys ||= billing_segments_scope
          .joins(contract_rate_card: {product: {billable_metric: :filters}})
          .distinct
          .pluck("billable_metric_filters.key")
      end

      def event_store
        @event_store ||= Events::Stores::StoreFactory.new_instance(
          organization:,
          context: Events::Stores::EventContext.from(contract:),
          boundaries: {
            from_datetime: target_segments.map(&:started_at).min,
            to_datetime: target_segments.map(&:ended_at).max
          }
        )
      end
    end
  end
end
