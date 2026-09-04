# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    class BillingSegmentsResolver
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

        combinations_by_code = combinations.group_by(&:first)
        result = {}

        target_segments.each do |billing_segment|
          code = billing_segment.contract_rate_card.product.billable_metric.code
          next if combinations_by_code[code].blank?

          target_filter = Events::BillingPeriodFilters::FilterTarget.from_billing_segment(billing_segment:)

          combinations_by_code[code].each do |(_code, properties, last_seen_at)|
            event = ::Event.new(code:, properties:)
            matching = Events::BillingPeriodFilters::EventMatchingService.call(target_filter:, event:).matching_filters

            if matching.empty?
              record(result, target_filter.target_key, nil, last_seen_at)
            else
              matching.each { |filter| record(result, target_filter.target_key, filter.id, last_seen_at) }
            end
          end
        end

        result
      end

      private

      attr_reader :contract, :billing_segments, :codes, :with_last_seen_at

      delegate :organization, to: :contract

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

      def record(accumulator, target_key, filter_id, last_seen_at)
        bucket = (accumulator[target_key] ||= {})
        current = bucket[filter_id]

        if !bucket.key?(filter_id) || (last_seen_at && (current.nil? || last_seen_at > current))
          bucket[filter_id] = last_seen_at
        end
      end
    end
  end
end
