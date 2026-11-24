# frozen_string_literal: true

module Fees
  class ChargeService
    class MeteredItem
      # Closing units per pricing group, kept until the last segment that uses them.
      class SegmentUsageCarryover
        ACTIONS = {
          reset: :reset, # Grouping changed: discard prior balances and start with this segment's units.
          carry: :carry, # Price this segment's tiers using each group's opening balance.
          track: :track # Price this segment locally, but save its units for a later tiered switch.
        }.freeze
        private_constant :ACTIONS

        class ClosingBalance
          def initialize(coverage_end:)
            @coverage_end = coverage_end
            @units_by_group = {}
          end

          def continues_at?(started_at:)
            @coverage_end == started_at
          end

          def advance_past(segment)
            @coverage_end = BillingSegment.exclusive_end(segment.ended_at)
          end

          def reset!
            @units_by_group.clear
          end

          def opening_for(group)
            @units_by_group.fetch(group.grouped_by, 0)
          end

          def record_and_return_opening(group)
            opening = opening_for(group)
            @units_by_group[group.grouped_by] = opening + group.aggregation
            opening
          end
        end
        private_constant :ClosingBalance
        private_class_method :new

        delegate :empty?, to: :action_by_segment

        def initialize(action_by_segment:, coverage_started_at:, last_carryover_segment:)
          @action_by_segment = action_by_segment
          @last_carryover_segment = last_carryover_segment
          @closing_balance = ClosingBalance.new(coverage_end: coverage_started_at)
        end

        EMPTY = new(action_by_segment: {}.freeze, coverage_started_at: nil, last_carryover_segment: nil).freeze
        private_constant :EMPTY

        def self.empty
          EMPTY
        end

        def self.for(segments:, coverage_started_at:)
          return empty if segments.size < 2

          first = segments.first
          return empty unless first.organization.product_catalog_enabled? && first.contract_rate_card.rate_card.product.metered?

          action_by_segment = {first => ACTIONS.fetch(:track)}
          last_carryover_segment = nil
          segments.each_cons(2) do |previous, segment|
            action = action_for(previous:, segment:)
            action_by_segment[segment] = action
            last_carryover_segment = segment if action == ACTIONS.fetch(:carry)
          end

          if last_carryover_segment
            new(action_by_segment:, coverage_started_at:, last_carryover_segment:)
          else
            empty
          end
        end

        def self.action_for(previous:, segment:)
          # shortcut: assume effective exclusions stay stable; revisit when handling overlapping product filters.
          if Array(previous.rate_properties["pricing_group_keys"]) != Array(segment.rate_properties["pricing_group_keys"])
            return ACTIONS.fetch(:reset)
          end

          rate = segment.rate
          if rate.graduated? || rate.graduated_percentage? || rate.volume?
            ACTIONS.fetch(:carry)
          else
            ACTIONS.fetch(:track)
          end
        end
        private_class_method :action_for

        def accumulate(metered_item:, groups:, &block)
          segment = metered_item.billing_segment
          action = action_by_segment.fetch(segment) { return }
          return unless metered_item.accumulate?
          return unless closing_balance.continues_at?(started_at: segment.started_at)

          return finish!(groups, &block) if segment == last_carryover_segment

          closing_balance.reset! if action == ACTIONS.fetch(:reset)
          groups.each do |group|
            opening = closing_balance.record_and_return_opening(group)
            yield group, opening if action == ACTIONS.fetch(:carry)
          end
          closing_balance.advance_past(segment)
        end

        private

        attr_reader :action_by_segment, :closing_balance, :last_carryover_segment

        def finish!(groups)
          groups.each { |group| yield group, closing_balance.opening_for(group) }
          action_by_segment.clear
          @closing_balance = nil
        end
      end
    end
  end
end
