# frozen_string_literal: true

module Charges
  module Validators
    # Catalog volume tiers are adjacent: each starts where the previous one ends
    # (see RateProperties), where v1 volume ranges start one unit after it.
    class AdjacentVolumeService < VolumeService
      private

      def next_from_value(range)
        range[:to_value] || 0
      end
    end
  end
end
