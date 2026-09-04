# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    class BillingSegmentsResolver < BaseResolver
      def initialize(contract:, billing_segments:, codes: nil, with_last_seen_at: true)
        @contract = contract
        @billing_segments = billing_segments
        @codes = codes
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
        @target_segments ||= billing_segments_scope.filter_map do |billing_segment|
          product = billing_segment.contract_rate_card.product
          next if product.billable_metric.nil?
          next if codes.present? && codes.exclude?(product.billable_metric.code)

          billing_segment
        end
      end

      def billing_segments_scope
        scope = billing_segments
        if scope.respond_to?(:includes)
          scope = scope.includes(
            contract_rate_card: {product: [:billable_metric, {filters: {values: :billable_metric_filter}}]}
          )
        end

        scope.to_a
      end

      def metric_codes
        @metric_codes ||= codes.presence || target_segments.map do |segment|
          segment.contract_rate_card.product.billable_metric.code
        end.uniq
      end

      def billable_metric_filter_keys
        @billable_metric_filter_keys ||= BillableMetricFilter
          .where(billable_metric_id: target_segments.map { |segment| segment.contract_rate_card.product.billable_metric_id })
          .distinct
          .pluck(:key)
      end

      def event_store
        @event_store ||= Events::Stores::StoreFactory.new_instance(
          organization:,
          subscription: contract,
          boundaries: {
            from_datetime: target_segments.map(&:started_at).min,
            to_datetime: target_segments.map(&:ended_at).max
          }
        )
      end
    end
  end
end
