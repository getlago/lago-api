# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    class BaseResolver
      def filter_targets
        if organization.pre_filter_events?
          filter_targets_from_pre_enriched_events
        else
          filter_targets_from_events
        end
      end

      private

      def filter_targets_from_events
        combinations = event_values_with_history do |**options|
          event_store.distinct_codes_and_property_combinations(filter_keys: billable_metric_filter_keys, **options)
        end

        filter_targets_from_combinations(
          combinations:,
          targets: targets_with_events(combinations.map(&:first).uniq),
          result: recurring_event_filter_targets
        )
      end

      def event_values_with_history
        values = yield(codes: non_recurring_metric_codes, with_last_seen_at:)

        # Recurring usage carries over all-time, so its lazy cache key must reflect events ingested
        # for prior periods.
        if recurring_metric_codes.any?
          values += yield(codes: recurring_metric_codes, include_all_history: true, with_last_seen_at:)
        end

        values
      end

      def non_recurring_metric_codes
        @non_recurring_metric_codes ||= metric_codes.to_a - recurring_metric_codes
      end

      def recurring_event_filter_targets
        current_recurring_targets.each_with_object({}) do |source, result|
          target = filter_target_for(source)
          target.filters.each { |filter| record(result, target.target_key, filter.id, period_start) }
          record(result, target.target_key, nil, period_start)
        end
      end

      def filter_targets_from_combinations(combinations:, targets:, result: {})
        combinations_by_code = combinations.group_by(&:first)

        targets.each do |target|
          target_filter = filter_target_for(target)
          code = target_filter.billable_metric.code
          next if combinations_by_code[code].blank?

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
