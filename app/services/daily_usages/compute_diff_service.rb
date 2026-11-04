# frozen_string_literal: true

module DailyUsages
  class ComputeDiffService < BaseService
    Result = BaseResult[:usage_diff]

    # Above this number of value cells, edited filters are split among all the current filters
    MAX_VALUE_CELLS = 10_000
    DECIMAL_SCALE = 10**20
    OTHER_VALUE = Object.new.freeze

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

    def apply_filters_diff(previous_parent, current_parent)
      current_filters = current_parent["filters"]
      return if current_filters.empty?

      previous_filters = previous_parent["filters"].presence || [unfiltered_bucket(previous_parent)]

      if previous_filters.map { |fu| fu["values"] }.to_set == current_filters.map { |fu| fu["values"] }.to_set
        previous_index = previous_filters.index_by { |fu| fu["values"] }
        current_filters.each { |fu| apply_bucket_diff(previous_index[fu["values"]], fu) }
      else
        reroute_filters(previous_filters, current_filters)
      end
    end

    def unfiltered_bucket(parent)
      parent.slice("amount_cents", "units", "events_count")
        .merge("values" => nil, "presentation_breakdowns" => Array(parent["presentation_breakdowns"]))
    end

    def apply_bucket_diff(previous_filter, current_filter)
      apply_diff(previous_filter, current_filter)
      apply_presentation_breakdowns_diff(previous_filter, current_filter)
    end

    def reroute_filters(previous_filters, current_filters)
      single, multiple = previous_filters.zip(filter_routes(previous_filters, current_filters))
        .partition { |_filter, receivers| receivers.one? }

      single.each { |filter, receivers| apply_bucket_diff(filter, receivers.first) }

      multiple.flat_map { |filter, receivers| deduction_plan(filter, receivers) }
        .each { |slot, part| subtract([slot], [part]) }
    end

    def deduction_plan(filter, receivers)
      plan = []
      breakdown_units = Array.new(receivers.size, BigDecimal(0))
      covered = Array(filter["presentation_breakdowns"]).any?

      Array(filter["presentation_breakdowns"]).each do |breakdown|
        indexed_slots = receivers.each_with_index.filter_map do |receiver, index|
          match = Array(receiver["presentation_breakdowns"]).find { |pb| pb["presentation_by"] == breakdown["presentation_by"] }
          [[match, "units"], index] if match
        end

        if indexed_slots.empty?
          covered = false
          next
        end

        parts = split(slot_value([breakdown, "units"]), indexed_slots.map(&:first))
        indexed_slots.zip(parts).each do |(slot, index), part|
          plan << [slot, part]
          breakdown_units[index] += part
        end
      end

      units = slot_value([filter, "units"])
      unit_slots = receivers.map { |receiver| [receiver, "units"] }
      unit_parts = (covered && breakdown_units.sum == units) ? breakdown_units : split(units, unit_slots)

      amount = slot_value([filter, "amount_cents"])
      amount_slots = receivers.map { |receiver| [receiver, "amount_cents"] }
      amount_parts = if units.positive?
        allocate(amount, unit_parts.map { |part| part.to_r / units.to_r }, integer: integer_slots?(amount_slots))
      else
        split(amount, amount_slots)
      end

      event_slots = receivers.map { |receiver| [receiver, "events_count"] }
      event_parts = split(slot_value([filter, "events_count"]), event_slots)

      plan + unit_slots.zip(unit_parts) + amount_slots.zip(amount_parts) + event_slots.zip(event_parts)
    end

    def filter_routes(previous_filters, current_filters)
      cells = value_cells(previous_filters + current_filters)
      return Array.new(previous_filters.size, current_filters) unless cells

      previous_values = previous_filters.map { |fu| fu["values"] }.to_set
      routes = Array.new(previous_filters.size) { Set.new }

      cells.each do |cell|
        current_billers = billers(cell, current_filters)

        billers(cell, previous_filters).each do |index|
          values = previous_filters[index]["values"]
          same = current_billers.select { |i| current_filters[i]["values"] == values }
          # A tie is won by the oldest filter, so by a filter that existed before the edit
          kept = current_billers.select { |i| previous_values.include?(current_filters[i]["values"]) }

          routes[index].merge(same.presence || kept.presence || current_billers)
        end
      end

      routes.map { |indexes| indexes.empty? ? current_filters : indexes.sort.map { |i| current_filters[i] } }
    end

    def value_cells(filters)
      tokens = filters.filter_map { |fu| fu["values"] }.flat_map(&:to_a).group_by(&:first).transform_values do |pairs|
        (pairs.flat_map { |_key, allowed| Array(allowed) } - [ChargeFilterValue::ALL_FILTER_VALUES]).uniq + [OTHER_VALUE]
      end
      return [{}] if tokens.empty?
      return if tokens.values.map(&:size).reduce(:*) > MAX_VALUE_CELLS

      first, *rest = tokens.values
      first.product(*rest).map { |combination| tokens.keys.zip(combination).to_h }
    end

    def billers(cell, filters)
      matching = filters.each_index.select do |index|
        filters[index]["values"]&.all? do |key, allowed|
          Array(allowed).include?(ChargeFilterValue::ALL_FILTER_VALUES) || Array(allowed).include?(cell[key])
        end
      end

      if matching.empty?
        filters.each_index.select { |index| filters[index]["values"].nil? }
      else
        precedence = ->(index) { filter_precedence(filters[index]["values"]) }
        best = matching.map(&precedence).min
        matching.select { |index| precedence.call(index) == best }
      end
    end

    # Same order as ChargeFilter#precedence, where an all-values filter ranks below any explicit list
    def filter_precedence(values)
      size = values.sum do |_key, allowed|
        Array(allowed).include?(ChargeFilterValue::ALL_FILTER_VALUES) ? Float::INFINITY : Array(allowed).size
      end

      [-values.size, size]
    end

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

    # Largest remainder method: parts add up to the total and a zero share gets nothing
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
