# frozen_string_literal: true

module Fees
  class ChargeService
    module Trackers
      # Rounded units select tiers without rebilling earlier segments.
      class CycleCarryoverUnits < Carryover
        def self.carry_segment?(segment)
          rate = segment.rate
          rate.graduated? || rate.graduated_percentage? || rate.volume?
        end

        def self.last_segment(segments, action_by_segment)
          segments.rfind { action_by_segment[it] == :carry }
        end

        private_class_method :carry_segment?, :last_segment

        def apply_carry_over? = !empty?

        private

        def quantity_for(group) = group.aggregation
      end
    end
  end
end
