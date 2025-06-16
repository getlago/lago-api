# frozen_string_literal: true

module Validators
  module RangeBoundsValidator
    def valid_bounds?(range, index, next_from_value)
      range[:from_value] == next_from_value && (
        index == (ranges.size - 1) && range[:to_value].nil? ||
        index < (ranges.size - 1) && (range[:to_value] || 0) > range[:from_value]
      )
    end
  end
end
