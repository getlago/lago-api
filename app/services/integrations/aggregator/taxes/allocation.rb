# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      # NOTE: Rounding each share on its own leaves the shares adding up to something other than
      #       the figure the provider priced. The whole difference cannot go on one share: shares
      #       of equal weight all round the same way, so it grows with their number and would
      #       drive that share negative. Handing out one cent at a time, largest fractional part
      #       first, spends the figure exactly and keeps every share within a cent of its own.
      module Allocation
        def self.call(total, weights)
          return Array.new(weights.size, 0) if total.nil? || total.zero? || weights.sum.zero?

          exact = weights.map { |weight| total.to_d * weight.to_d / weights.sum }
          allocated = exact.map(&:truncate)
          residue = total.round - allocated.sum
          step = residue.negative? ? -1 : 1

          exact.each_with_index
            .sort_by { |value, index| [-(value - value.truncate) * step, index] }
            .first(residue.abs)
            .each { |_value, index| allocated[index] += step }

          allocated
        end
      end
    end
  end
end
