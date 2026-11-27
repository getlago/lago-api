# frozen_string_literal: true

module Fees
  class ChargeService
    module Trackers
      class Carryover
        ACTIONS = {
          reset: :reset, # Grouping changed: discard prior balances and start with this segment's units.
          carry: :carry, # Apply each group's opening balance to this segment.
          track: :track # Accumulate quantities without applying the opening balance.
        }.freeze
        private_constant :ACTIONS

        private_class_method :new

        delegate :empty?, to: :action_by_segment

        def initialize(action_by_segment:, coverage_started_at:, last_carryover_segment:)
          @action_by_segment = action_by_segment
          @last_carryover_segment = last_carryover_segment
          @coverage_end = coverage_started_at
          @units_by_group = Hash.new(0)
        end

        def self.for(segments:, coverage_started_at:)
          action_by_segment = {segments.first => ACTIONS.fetch(:track)}
          segments.each_cons(2) do |previous, segment|
            action_by_segment[segment] = action_for(previous:, segment:)
          end
          last_carryover_segment = last_segment(segments, action_by_segment)

          if last_carryover_segment
            new(action_by_segment:, coverage_started_at:, last_carryover_segment:)
          else
            BillingSegments::EMPTY_CYCLE_USAGE_TRACKER
          end
        end

        def self.action_for(previous:, segment:)
          # shortcut: assume effective exclusions stay stable; revisit when handling overlapping product filters.
          if Array(previous.rate_properties["pricing_group_keys"]) != Array(segment.rate_properties["pricing_group_keys"])
            return ACTIONS.fetch(:reset)
          end

          if carry_segment?(segment)
            ACTIONS.fetch(:carry)
          else
            ACTIONS.fetch(:track)
          end
        end
        private_class_method :action_for

        def apply_closing_values?(groups: []) = false

        def carryover_variation? = false

        def apply_carry_over? = false

        def each_opening_balance(metered_item:, groups:, &block)
          segment = metered_item.billing_segment
          action = action_by_segment.fetch(segment) { return }
          return unless @coverage_end == segment.started_at

          @units_by_group.clear if action == ACTIONS.fetch(:reset)
          return finish!(groups, &block) if segment == last_carryover_segment

          groups.each do |group|
            key = group.grouped_by
            opening = @units_by_group[key]
            @units_by_group[key] = opening + quantity_for(group)
            yield group, opening if action == ACTIONS.fetch(:carry)
          end
          @coverage_end = BillingSegment.exclusive_end(segment.ended_at)
        end

        private

        attr_reader :action_by_segment, :last_carryover_segment

        def finish!(groups)
          groups.each { |group| yield group, @units_by_group[group.grouped_by] }
          action_by_segment.clear
          @units_by_group.clear
        end
      end
    end
  end
end
