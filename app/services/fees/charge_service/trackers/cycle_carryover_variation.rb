# frozen_string_literal: true

module Fees
  class ChargeService
    module Trackers
      # Raw variation seeds weighted usage independently of pricing tiers.
      class CycleCarryoverVariation < Carryover
        def self.carry_segment?(_segment) = true

        def self.last_segment(segments, _action_by_segment) = segments.last

        private_class_method :carry_segment?, :last_segment

        def carryover_variation? = true

        def opening_variations(metered_item:)
          segment = metered_item.billing_segment
          action = action_by_segment[segment]
          return {} unless action && @coverage_end == segment.started_at

          (action == ACTIONS.fetch(:reset)) ? {} : @units_by_group.dup
        end

        private

        def quantity_for(group) = group.variation
      end
    end
  end
end
