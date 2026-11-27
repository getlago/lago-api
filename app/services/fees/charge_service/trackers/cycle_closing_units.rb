# frozen_string_literal: true

module Fees
  class ChargeService
    module Trackers
      # Max and Latest bill the closing value even if a group has no event in this segment.
      class CycleClosingUnits
        def initialize(maximum:)
          @maximum = maximum
          @values = {}
        end

        def apply_closing_values?(groups: [])
          @values.any? || groups.any? { |group| group.count.to_i.positive? }
        end

        def apply_carry_over? = false

        def carryover_variation? = false

        def each_closing_value(metered_item:, groups:)
          values = closing_values_for(metered_item:, groups:)
          return if values.empty?
          return yield(groups.first, values.fetch(nil), nil) if @group_keys.empty?

          # A grouped query with no observations may return a synthetic zero row.
          local = groups.select { |group| group.count.to_i.positive? }
          local.each { |group| yield group, values.fetch(group.grouped_by), group.grouped_by }
          (values.keys - local.map(&:grouped_by)).each { |key| yield nil, values.fetch(key), key }
        end

        private

        def closing_values_for(metered_item:, groups:)
          segment = metered_item.billing_segment
          keys = metered_item.pricing_group_keys
          @values.clear unless @coverage_end == segment.started_at && @group_keys == keys
          @coverage_end = BillingSegment.exclusive_end(segment.ended_at)
          @group_keys = keys

          groups.each do |group|
            next unless group.count.to_i.positive?

            key = group.grouped_by
            previous_segment_closing_value = @values[key]
            @values[key] = if @maximum && previous_segment_closing_value
              [previous_segment_closing_value, group.aggregation].max
            else
              group.aggregation
            end
          end
          @values
        end
      end
    end
  end
end
