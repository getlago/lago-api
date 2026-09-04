# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    class BaseResolver
      private

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
