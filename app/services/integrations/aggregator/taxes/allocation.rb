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

          exact = precise(total, weights)
          allocated = exact.map(&:truncate)
          residue = total.round - allocated.sum
          step = residue.negative? ? -1 : 1

          exact.each_with_index
            .sort_by { |value, index| [-(value - value.truncate) * step, index] }
            .first(residue.abs)
            .each { |_value, index| allocated[index] += step }

          allocated
        end

        # Preserve booked proportions unless every group rounded down to zero.
        # Accessors can also be callables for prorated credit-note amounts.
        def self.by_group(total, groups, amount: :amount_cents, precise_amount: :precise_amount_cents)
          weights = groups.map { |group| group.sum(&amount) }
          if weights.sum.zero?
            weights = groups.map { |group| group.sum(&precise_amount) }
          end
          call(total, weights)
        end

        def self.precise(total, weights)
          decimal_weights = weights.map(&:to_d)
          total_weight = decimal_weights.sum
          if total.nil? || total.zero? || total_weight.zero?
            Array.new(weights.size, 0.to_d)
          else
            decimal_weights.map { |weight| total.to_d * weight / total_weight }
          end
        end
      end
    end
  end
end
