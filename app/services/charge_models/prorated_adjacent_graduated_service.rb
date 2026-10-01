# frozen_string_literal: true

module ChargeModels
  # Prorated graduated pricing for tiers that touch, each starting where the
  # previous one ends: the shape of catalog rates. An event's units fill the
  # tiers between the usage before and after it, so an addition fills upward
  # and a removal of a sum empties the top tiers first, and each tier's share
  # is priced at the event's proration. Nothing steps by whole units, so bounds
  # can be decimals. A unique count keeps each id at the tier it entered, as
  # the step calculator does.
  class ProratedAdjacentGraduatedService < ProratedGraduatedService
    protected

    def ranges
      @ranges ||= properties["graduated_ranges"]&.map(&:with_indifferent_access)
    end

    def compute_amount
      # Catalog tiers stored before they were defined by their upper bound
      # still step by one unit: the step calculator prices those.
      return super if ranges.size >= 2 && !AdjacentRanges.adjacent?(ranges)
      return result_with_flat_amount(0, 0, 0) if units.zero?

      full_sum = BigDecimal(0)
      max_full_sum = BigDecimal(0)
      amount = BigDecimal(0)

      events.each do |full, prorated|
        next if left_out?(full, prorated, full_sum)

        amount += prorated / full * tier_cost(full_sum, full_sum + full)
        full_sum += full
        max_full_sum = full_sum if full_sum > max_full_sum
      end

      result_with_flat_amount(amount, full_sum, max_full_sum)
    end

    private

    def events
      full = per_event_aggregation_result.event_aggregation
      prorated = if per_event_aggregation_result.respond_to?(:event_prorated_aggregation)
        per_event_aggregation_result.event_prorated_aggregation
      else
        []
      end

      prorated.each_with_index.map { |value, index| [BigDecimal(full[index].to_s), BigDecimal(value.to_s)] }
    end

    # The events the step calculator leaves out too: an addition worth nothing
    # in the period, and a removal whose addition was left out.
    def left_out?(full, prorated, full_sum)
      full.zero? || (prorated.zero? && (full.positive? || (full_sum + full).negative?))
    end

    # Price of the usage between two totals: positive when usage rises, negative
    # when it falls. Usage below zero sits in no tier.
    def tier_cost(before, after)
      low, high = [before, after].minmax

      cost = ranges.sum do |range|
        lower = BigDecimal(range[:from_value].to_s)
        upper = range[:to_value] && BigDecimal(range[:to_value].to_s)
        covered = [high, upper].compact.min - [low, lower].max
        covered.positive? ? covered * BigDecimal(range[:per_unit_amount]) : 0
      end

      (after >= before) ? cost : -cost
    end
  end
end
