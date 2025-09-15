# frozen_string_literal: true

module FixedCharges
  module FixedChargesEvents
    class AggregationService < AggregationBaseService
      def call
        events_in_range.last.try(:units) || 0
      end
    end
  end
end
