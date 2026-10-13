# frozen_string_literal: true

module DailyUsages
  class ComputeDiffService < BaseService
    Result = BaseResult[:usage_diff]

    # Above this number of value combinations, a dropped filter is routed by overlap only
    MAX_VALUE_COMBINATIONS = 1_000
    # Precision of the decimal parts (units) when splitting a dropped filter
    DECIMAL_SCALE = 10**20

    def initialize(daily_usage:, previous_daily_usage: nil)
      @daily_usage = daily_usage
      @previous_daily_usage = previous_daily_usage

      super
    end

    def call
      unless previous_daily_usage
        result.usage_diff = daily_usage.usage
        return result
      end

      diff = daily_usage.usage.deep_dup
      previous_usage = previous_daily_usage.usage

      previous_charges_index = previous_usage["charges_usage"].index_by { |cu| cu["charge"]["lago_id"] }

      diff["charges_usage"].each do |current_charge_usage|
        previous_charge_usage = previous_charges_index[current_charge_usage["charge"]["lago_id"]]
        next unless previous_charge_usage

        apply_diff(previous_charge_usage, current_charge_usage)
        apply_filters_diff(previous_charge_usage, current_charge_usage)
        apply_presentation_breakdowns_diff(previous_charge_usage, current_charge_usage)

        previous_grouped_index = previous_charge_usage["grouped_usage"].index_by { |gu| gu["grouped_by"] }
        current_charge_usage["grouped_usage"].each do |current_grouped_usage|
          previous_grouped_usage = previous_grouped_index[current_grouped_usage["grouped_by"]]
          next unless previous_grouped_usage

          apply_diff(previous_grouped_usage, current_grouped_usage)
          apply_filters_diff(previous_grouped_usage, current_grouped_usage)
          apply_presentation_breakdowns_diff(previous_grouped_usage, current_grouped_usage)
        end
      end

      diff["amount_cents"] = diff["charges_usage"].sum { |cu| cu["amount_cents"] }
      diff["taxes_amount_cents"] -= previous_common_taxes(diff, previous_usage, previous_charges_index)
      diff["total_amount_cents"] = diff["amount_cents"] + diff["taxes_amount_cents"]

      result.usage_diff = diff
      result
    end

    private

    attr_reader :daily_usage

    delegate :subscription, :usage_date, :from_datetime, :to_datetime, to: :daily_usage

    # Returns the most recent daily_usage for the same subscription and billing period that is
    # strictly older than the current usage_date.
    #
    # We intentionally do NOT restrict the lookup to `usage_date - 1.day`. On days without events,
    # no daily_usage row is saved (see DailyUsages::ComputeAllService `last_received_event_on`
    # guard and DailyUsages::ComputeService returning early when `current_usage.fees` is empty),
    # so the immediately preceding row may live several days back. Falling back to "full usage"
    # in those cases would double-count the gap days in downstream analytics that sum
    # `usage_diff` (see lago-data `data_pipeline/models/usage/usage_daily_base.sql`).
    def previous_daily_usage
      @previous_daily_usage ||= subscription.daily_usages
        .where(from_datetime:, to_datetime:)
        .where("usage_date < ?", usage_date)
        .order(usage_date: :desc)
        .first
    end

    # Prorates previous taxes based on how much of the previous amount came from charges
    # that still exist in the current snapshot. This avoids over-deducting taxes when charges
    # are added or removed between snapshots.
    #
    # Example: previous had charges A(100) + B(200) = 300 with 30 in taxes.
    # Current only has charge A. Common ratio = 100/300 = 1/3, so we deduct 10 (not 30).
    def previous_common_taxes(diff, previous_usage, previous_charges_index)
      return previous_usage["taxes_amount_cents"] unless previous_usage["amount_cents"].positive?

      previous_common_amount = diff["charges_usage"].sum do |cu|
        previous_charges_index.dig(cu["charge"]["lago_id"], "amount_cents") || 0
      end

      common_ratio = previous_common_amount.fdiv(previous_usage["amount_cents"])
      (previous_usage["taxes_amount_cents"] * common_ratio).round
    end

    # Filters have no stable identifier in the serialized usage, so they are matched on their values.
    # When a charge's filters are edited mid-period, the current snapshot (recomputed over the whole
    # period with the new filters) holds filters that did not exist in the previous snapshot, and the
    # previous snapshot holds filters that no longer exist. Without reconciliation, the new filters
    # keep their full period-to-date values as "diff" while the dropped filters' values are never
    # subtracted, so the filter diffs no longer add up to the parent diff.
    #
    # The values of each dropped filter are therefore deducted from the buckets its usage moved to (see
    # #receiving_filters). After diffing, each current filter holds what it gained since the previous
    # snapshot (its whole period-to-date value when it is new):
    # - presentation breakdowns are split among the receivers having the same breakdown, in proportion
    #   to their gains,
    # - units follow the breakdowns when those cover all the dropped units, and are otherwise split in
    #   proportion to the receivers' unit gains,
    # - the amount follows the units, as it was billed at the dropped filter's price,
    # - the events count is split in proportion to the receivers' event gains.
    #
    # Filter diffs then always add up to the parent diff. Each filter diff is exact when the usage of a
    # dropped filter moved to a single bucket, when no new usage was received, or when breakdowns tell
    # where the units went. Otherwise the split of the day's usage between the receivers is an estimate:
    # the snapshots do not tell which part of a bucket's gain was moved and which part is new.
    def apply_filters_diff(previous_parent, current_parent)
      current_filters = current_parent["filters"]
      current_values = current_filters.map { |fu| fu["values"] }.to_set
      previous_filters_index = previous_parent["filters"].index_by { |fu| fu["values"] }

      current_filters.each do |current_filter|
        previous_filter = previous_filters_index[current_filter["values"]]
        next unless previous_filter

        apply_diff(previous_filter, current_filter)
        apply_presentation_breakdowns_diff(previous_filter, current_filter)
      end

      previous_parent["filters"].each do |previous_filter|
        next if current_values.include?(previous_filter["values"])

        deduct_dropped_filter(previous_filter, receiving_filters(previous_filter["values"], current_filters))
      end
    end

    def deduct_dropped_filter(dropped_filter, receivers)
      unit_parts = deduct_breakdowns(dropped_filter, receivers)
      unit_parts ||= split(slot_value([dropped_filter, "units"]), receivers.map { |fu| [fu, "units"] })
      subtract(receivers.map { |fu| [fu, "units"] }, unit_parts)

      amount_slots = receivers.map { |fu| [fu, "amount_cents"] }
      dropped_units = slot_value([dropped_filter, "units"])
      amount_parts = if dropped_units.positive?
        shares = unit_parts.map { |part| part.to_r / dropped_units.to_r }
        allocate(slot_value([dropped_filter, "amount_cents"]), shares, integer: integer_slots?(amount_slots))
      else
        split(slot_value([dropped_filter, "amount_cents"]), amount_slots)
      end
      subtract(amount_slots, amount_parts)

      events_slots = receivers.map { |fu| [fu, "events_count"] }
      subtract(events_slots, split(slot_value([dropped_filter, "events_count"]), events_slots))
    end

    # Deducts the dropped filter's presentation breakdowns from the receivers' matching breakdowns.
    # Returns the units deducted from each receiver when the breakdowns cover all the dropped units,
    # nil otherwise.
    def deduct_breakdowns(dropped_filter, receivers)
      dropped_breakdowns = Array(dropped_filter["presentation_breakdowns"])
      unit_parts = Array.new(receivers.size, BigDecimal(0))
      covered = dropped_breakdowns.any?

      dropped_breakdowns.each do |dropped_breakdown|
        indexed_slots = receivers.each_with_index.filter_map do |fu, index|
          breakdown = Array(fu["presentation_breakdowns"])
            .find { |pb| pb["presentation_by"] == dropped_breakdown["presentation_by"] }
          [[breakdown, "units"], index] if breakdown
        end

        if indexed_slots.empty?
          covered = false
          next
        end

        slots = indexed_slots.map(&:first)
        parts = split(slot_value([dropped_breakdown, "units"]), slots)
        subtract(slots, parts)
        indexed_slots.each_with_index { |(_slot, index), position| unit_parts[index] += parts[position] }
      end

      covered &&= unit_parts.sum == slot_value([dropped_filter, "units"])
      unit_parts if covered
    end

    # The current filters billing the events a dropped filter used to bill. Each combination of the
    # dropped filter's values is billed by the most specific current filter matching it (most keys, then
    # fewest values, as ChargeFilter#precedence), or by the default bucket when none matches. When a
    # combination cannot be resolved from the values alone (a key the dropped filter does not constrain,
    # or a precedence tie), every candidate is kept.
    def receiving_filters(dropped_values, current_filters)
      default_bucket = current_filters.find { |fu| fu["values"].nil? }
      filters = current_filters.reject { |fu| fu["values"].nil? }
      combinations = value_combinations(dropped_values)

      receivers = if combinations.nil?
        filters.select { |fu| overlapping_values?(dropped_values, fu["values"]) } + [default_bucket]
      else
        combinations.flat_map { |combination| combination_receivers(combination, filters, default_bucket) }
      end

      receivers = receivers.compact.uniq(&:object_id)
      receivers.presence || current_filters
    end

    # Every key/value combination allowed by a filter, without the keys allowing all values. Returns nil
    # for the default bucket or when there are too many combinations to enumerate.
    def value_combinations(values)
      return if values.nil?

      constrained = values.reject { |_key, allowed| Array(allowed).include?(ChargeFilterValue::ALL_FILTER_VALUES) }
      return [{}] if constrained.empty?
      return if constrained.values.map { |allowed| Array(allowed).size }.reduce(:*) > MAX_VALUE_COMBINATIONS

      keys = constrained.keys
      first, *rest = keys.map { |key| Array(constrained[key]) }
      first.product(*rest).map { |combination| keys.zip(combination).to_h }
    end

    def combination_receivers(combination, filters, default_bucket)
      matching = []
      ambiguous = []

      filters.each do |fu|
        values = fu["values"]
        next unless values.all? { |key, allowed| !combination.key?(key) || allows?(allowed, combination[key]) }

        if values.keys.all? { |key| combination.key?(key) }
          matching << fu
        else
          ambiguous << fu
        end
      end

      precedence = ->(fu) { [-fu["values"].size, fu["values"].sum { |_key, allowed| Array(allowed).size }] }
      best = matching.map(&precedence).min
      billed_by = best ? matching.select { |fu| precedence.call(fu) == best } : [default_bucket]

      billed_by + ambiguous + (ambiguous.any? ? [default_bucket] : [])
    end

    def allows?(allowed, value)
      allowed = Array(allowed)
      allowed.include?(ChargeFilterValue::ALL_FILTER_VALUES) || allowed.include?(value)
    end

    # Whether events billed on one filter could be billed on the other: two filters overlap unless a key
    # they share has no value in common.
    def overlapping_values?(values, other_values)
      return true if values.nil? || other_values.nil?

      (values.keys & other_values.keys).all? do |key|
        allowed = Array(values[key])
        other_allowed = Array(other_values[key])

        [allowed, other_allowed].any? { |list| list.include?(ChargeFilterValue::ALL_FILTER_VALUES) } ||
          allowed.intersect?(other_allowed)
      end
    end

    # Splits total among the slots in proportion to what each one gained (equally when none gained
    # anything). A slot is a [hash, key] pair whose value is an integer (cents, events) or a decimal
    # string (units).
    def split(total, slots)
      return Array.new(slots.size, BigDecimal(0)) if total.zero? || slots.empty?

      gains = slots.map { |slot| [slot_value(slot), BigDecimal(0)].max.to_r }
      gains_total = gains.sum
      shares = if gains_total.positive?
        gains.map { |gain| gain / gains_total }
      else
        Array.new(slots.size, Rational(1, slots.size))
      end

      allocate(total, shares, integer: integer_slots?(slots))
    end

    def subtract(slots, parts)
      slots.zip(parts).each do |(hash, key), part|
        remaining = slot_value([hash, key]) - part
        hash[key] = if key == "units" || hash[key].is_a?(String)
          remaining.to_s
        elsif hash[key].is_a?(Integer)
          remaining.to_i
        else
          remaining.to_f
        end
      end
    end

    def integer_slots?(slots)
      slots.all? { |(hash, key)| hash[key].is_a?(Integer) }
    end

    def slot_value((hash, key))
      BigDecimal((hash[key] || 0).to_s)
    end

    # Splits total according to shares (exact fractions adding up to 1) with the largest remainder method:
    # each part gets the floor of its exact share, and the units left go one by one to the parts with the
    # largest fractions. Parts always add up to the total, have the sign of the total, and a zero share
    # gets nothing. Integer values (cents, events) are split into integers, decimals (units) at
    # DECIMAL_SCALE precision.
    def allocate(total, shares, integer:)
      return [] if shares.empty?

      scale = integer ? 1 : DECIMAL_SCALE
      scaled_total = (BigDecimal(total.to_s) * scale).round
      sign = scaled_total.negative? ? -1 : 1

      exact = shares.map { |share| scaled_total.abs * share }
      parts = exact.map(&:floor)
      leftover = scaled_total.abs - parts.sum
      exact.each_with_index.sort_by { |value, index| [-(value - value.floor), index] }
        .first(leftover).each { |_value, index| parts[index] += 1 }

      parts.map do |part|
        integer ? sign * part : BigDecimal(sign * part) / scale
      end
    end

    def apply_presentation_breakdowns_diff(previous_parent, current_parent)
      previous_index = Array(previous_parent["presentation_breakdowns"]).index_by { |pb| pb["presentation_by"] }

      current_parent.fetch("presentation_breakdowns", []).each do |current_breakdown|
        previous_breakdown = previous_index[current_breakdown["presentation_by"]]
        next unless previous_breakdown

        current_units = BigDecimal(current_breakdown["units"] || 0)
        previous_units = BigDecimal(previous_breakdown["units"] || 0)
        current_breakdown["units"] = (current_units - previous_units).to_s
      end
    end

    def apply_diff(previous_values, current_values)
      current_values["units"] = (BigDecimal(current_values["units"]) - BigDecimal(previous_values["units"])).to_s
      current_values["events_count"] -= previous_values["events_count"]
      current_values["amount_cents"] -= previous_values["amount_cents"]
    end
  end
end
