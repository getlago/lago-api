# frozen_string_literal: true

module DailyUsages
  class ComputeDiffService < BaseService
    Result = BaseResult[:usage_diff]

    # Above this number of value cells, edited filters are split among all the current filters
    MAX_VALUE_CELLS = 10_000
    DECIMAL_SCALE = 10**20
    OTHER_VALUE = :__other__
    FIT_DIGITS = 12
    MAX_FIT_ROUNDS = 10_000

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

        charge_id = current_charge_usage["charge"]["lago_id"]
        apply_diff(previous_charge_usage, current_charge_usage)
        apply_filters_diff(previous_charge_usage, current_charge_usage, charge_id)
        apply_presentation_breakdowns_diff(previous_charge_usage, current_charge_usage)

        previous_grouped_index = previous_charge_usage["grouped_usage"].index_by { |gu| gu["grouped_by"] }
        current_charge_usage["grouped_usage"].each do |current_grouped_usage|
          previous_grouped_usage = previous_grouped_index[current_grouped_usage["grouped_by"]]
          next unless previous_grouped_usage

          apply_diff(previous_grouped_usage, current_grouped_usage)
          apply_filters_diff(previous_grouped_usage, current_grouped_usage, charge_id)
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

    def apply_filters_diff(previous_parent, current_parent, charge_id)
      current_filters = current_parent["filters"]
      return if current_filters.empty?

      previous_filters = previous_parent["filters"]
      current_keys = current_filters.map { |fu| filter_key(fu) }.to_set

      # A filter only shows up once it gets its first event, so new buckets alone are not an edit
      if previous_filters.empty? || previous_filters.any? { |fu| !current_keys.include?(filter_key(fu)) }
        reroute_filters(previous_filters.presence || [unfiltered_bucket(previous_parent)], current_filters, charge_id)
      else
        previous_index = previous_filters.index_by { |fu| filter_key(fu) }
        current_filters.each do |fu|
          previous_filter = previous_index[filter_key(fu)]
          apply_bucket_diff(previous_filter, fu) if previous_filter
        end
      end
    end

    def filter_key(filter)
      filter["values"]&.transform_values { |allowed| Array(allowed).sort }
    end

    def unfiltered_bucket(parent)
      parent.slice("amount_cents", "units", "events_count")
        .merge("values" => nil, "presentation_breakdowns" => Array(parent["presentation_breakdowns"]))
    end

    def apply_bucket_diff(previous_filter, current_filter)
      apply_diff(previous_filter, current_filter)
      apply_presentation_breakdowns_diff(previous_filter, current_filter)
    end

    def reroute_filters(previous_filters, current_filters, charge_id)
      single, multiple = previous_filters.zip(filter_routes(previous_filters, current_filters, charge_id))
        .partition { |_filter, receivers| receivers.one? }

      single.each { |filter, receivers| apply_bucket_diff(filter, receivers.first) }

      claims = Hash.new do |hash, key|
        hash[key] = if key.is_a?(Array)
          breakdown_claims(multiple, key.last)
        else
          fit_claims(multiple.map { |filter, receivers| [filter, [filter, key], receivers.map { |r| [r, key] }] })
        end
      end

      multiple.flat_map { |filter, receivers| deduction_plan(filter, receivers, claims) }
        .each { |slot, part| subtract([slot], [part]) }
    end

    def breakdown_claims(multiple, presentation_by)
      fit_claims(
        multiple.filter_map do |filter, receivers|
          breakdown = find_breakdown(filter, presentation_by)
          next unless breakdown

          [filter, [breakdown, "units"], receivers.filter_map { |r| find_breakdown(r, presentation_by)&.then { |pb| [pb, "units"] } }]
        end
      )
    end

    def find_breakdown(filter, presentation_by)
      Array(filter["presentation_breakdowns"]).find { |pb| pb["presentation_by"] == presentation_by }
    end

    # The share of each receiver every split filter takes, so that each one takes its own usage and no receiver
    # gives more than it holds. Fitted by alternately scaling each filter to its usage and capping each receiver.
    def fit_claims(entries)
      receivers = entries.flat_map { |_filter, _total, slots| slots.map(&:first) }
      if receivers.uniq(&:object_id).size == receivers.size
        return entries.to_h { |filter, _total, slots| [filter.object_id, Array.new(slots.size, 1)] }
      end

      capacity = ->(slot) { [slot_value(slot), BigDecimal(0)].max.to_r }
      caps = entries.flat_map(&:last).to_h { |slot| [slot.first.object_id, capacity.call(slot)] }
      totals = entries.map { |_filter, total, _slots| capacity.call(total).to_f }
      usable = usable_edges(
        entries.map { |_filter, total, _slots| capacity.call(total) },
        entries.map { |_filter, _total, slots| slots.map { |slot| slot.first.object_id } },
        caps
      )
      rows = entries.each_with_index.map do |(_filter, _total, slots), i|
        slots.each_with_index.map { |slot, j| usable[i][j] ? caps[slot.first.object_id].to_f : 0.0 }
      end

      scale = [*caps.values, *totals].max
      grid = scale.positive? ? Rational(10)**(Math.log10(scale).floor - FIT_DIGITS) : 1

      MAX_FIT_ROUNDS.times do
        previous_rows = rows.map(&:dup)

        rows.each_with_index do |row, index|
          sum = row.sum
          row.map! { |value| value * totals[index] / sum } if sum.positive?
        end

        columns = Hash.new(0.0)
        entries.each_with_index do |(_filter, _total, slots), i|
          slots.each_with_index { |slot, j| columns[slot.first.object_id] += rows[i][j] }
        end
        entries.each_with_index do |(_filter, _total, slots), i|
          slots.each_with_index do |slot, j|
            cap = caps[slot.first.object_id].to_f
            rows[i][j] *= cap / columns[slot.first.object_id] if columns[slot.first.object_id] > cap
          end
        end

        break if rows.flatten.zip(previous_rows.flatten).all? { |value, previous| (value - previous).abs < grid / 100 }
      end

      entries.each_with_index.to_h do |(filter, _total, slots), i|
        shares = slots.each_with_index.map do |slot, j|
          cap = caps[slot.first.object_id]
          cap.positive? ? (rows[i][j] / grid).round * grid / cap : Rational(1, slots.size)
        end
        [filter.object_id, shares]
      end
    end

    # The fit only reaches a zero share slowly, so the edges no valid split can use are removed first. With an
    # exact max flow, an unused edge can carry usage only if the residual graph leads back from its receiver to its
    # filter.
    def usable_edges(totals, edges, caps)
      flows = edges.map { |row| Array.new(row.size, Rational(0)) }
      row_flow = ->(i) { flows[i].sum }
      column_flow = ->(id) { edges.each_with_index.sum { |row, i| row.each_with_index.sum { |rid, j| (rid == id) ? flows[i][j] : 0 } } }

      neighbors = lambda do |node|
        kind, index = node
        case kind
        when :source
          totals.each_index.filter_map { |i| [:row, i] if row_flow.call(i) < totals[i] }
        when :row
          edges[index].uniq.map { |id| [:column, id] } + (row_flow.call(index).positive? ? [[:source]] : [])
        when :column
          backward = edges.each_with_index.flat_map { |row, i| row.each_index.select { |j| row[j] == index && flows[i][j].positive? }.map { [:row, i] } }
          backward + ((column_flow.call(index) < caps[index]) ? [[:sink]] : [])
        when :sink
          caps.keys.select { |id| column_flow.call(id).positive? }.map { |id| [:column, id] }
        end
      end

      path_to = lambda do |from, to|
        parents = {from => nil}
        queue = [from]
        until queue.empty?
          node = queue.shift
          return parents if node == to

          neighbors.call(node).each do |neighbor|
            next if parents.key?(neighbor)

            parents[neighbor] = node
            queue << neighbor
          end
        end
        nil
      end

      while (parents = path_to.call([:source], [:sink]))
        path = [[:sink]]
        path.unshift(parents[path.first]) while parents[path.first]
        steps = path.each_cons(2).to_a

        room = steps.map do |(kind, index), (next_kind, next_index)|
          if kind == :source then totals[next_index] - row_flow.call(next_index)
          elsif next_kind == :sink then caps[index] - column_flow.call(index)
          elsif kind == :row then nil
          else edges[next_index].each_index.select { |j| edges[next_index][j] == index }.sum { |j| flows[next_index][j] }
          end
        end.compact.min

        steps.each do |(kind, index), (next_kind, next_index)|
          if kind == :row && next_kind == :column
            flows[index][edges[index].index(next_index)] += room
          elsif kind == :column && next_kind == :row
            left = room
            edges[next_index].each_index.select { |j| edges[next_index][j] == index }.each do |j|
              taken = [left, flows[next_index][j]].min
              flows[next_index][j] -= taken
              left -= taken
            end
          end
        end
      end

      edges.each_with_index.map do |row, i|
        row.each_with_index.map { |id, j| flows[i][j].positive? || path_to.call([:column, id], [:row, i]).present? }
      end
    end

    def deduction_plan(filter, receivers, claims)
      plan = []
      breakdown_units = Array.new(receivers.size, BigDecimal(0))
      covered = Array(filter["presentation_breakdowns"]).any?

      Array(filter["presentation_breakdowns"]).each do |breakdown|
        indexed_slots = receivers.each_with_index.filter_map do |receiver, index|
          match = find_breakdown(receiver, breakdown["presentation_by"])
          [[match, "units"], index] if match
        end

        if indexed_slots.empty?
          covered = false
          next
        end

        shares = claims[[:breakdown, breakdown["presentation_by"]]][filter.object_id]
        parts = split(slot_value([breakdown, "units"]), indexed_slots.map(&:first), shares)
        indexed_slots.zip(parts).each do |(slot, index), part|
          plan << [slot, part]
          breakdown_units[index] += part
        end
      end

      units = slot_value([filter, "units"])
      unit_slots = receivers.map { |receiver| [receiver, "units"] }
      unit_parts = if covered && breakdown_units.sum == units
        breakdown_units
      else
        split(units, unit_slots, claims["units"][filter.object_id])
      end

      amount = slot_value([filter, "amount_cents"])
      amount_slots = receivers.map { |receiver| [receiver, "amount_cents"] }
      amount_parts = if units.positive?
        allocate(amount, unit_parts.map { |part| part.to_r / units.to_r }, integer: integer_slots?(amount_slots))
      else
        split(amount, amount_slots, claims["amount_cents"][filter.object_id])
      end

      event_slots = receivers.map { |receiver| [receiver, "events_count"] }
      event_parts = split(slot_value([filter, "events_count"]), event_slots, claims["events_count"][filter.object_id])

      plan + unit_slots.zip(unit_parts) + amount_slots.zip(amount_parts) + event_slots.zip(event_parts)
    end

    def filter_routes(previous_filters, current_filters, charge_id)
      previous_expanded = previous_filters.map { |fu| expand_all_values(fu["values"], charge_id) }
      current_expanded = current_filters.map { |fu| expand_all_values(fu["values"], charge_id) }

      cells = value_cells(previous_expanded + current_expanded)
      return Array.new(previous_filters.size, current_filters) unless cells

      previous_keys = previous_filters.map { |fu| filter_key(fu) }.to_set
      routes = Array.new(previous_filters.size) { Set.new }

      cells.each do |cell|
        current_billers = billers(cell, current_expanded)

        billers(cell, previous_expanded).each do |index|
          key = filter_key(previous_filters[index])
          same = current_billers.select { |i| filter_key(current_filters[i]) == key }
          # A tie is won by the oldest filter, so by a filter that existed before the edit
          kept = current_billers.select { |i| previous_keys.include?(filter_key(current_filters[i])) }

          routes[index].merge(same.presence || kept.presence || current_billers)
        end
      end

      routes.map { |indexes| indexes.empty? ? current_filters : indexes.sort.map { |i| current_filters[i] } }
    end

    # Billing matches an all-values filter on the values of the billable metric filter
    def expand_all_values(values, charge_id)
      values&.to_h do |key, allowed|
        all_values = metric_filter_values(charge_id)[key] if Array(allowed).include?(ChargeFilterValue::ALL_FILTER_VALUES)
        [key, all_values || allowed]
      end
    end

    def metric_filter_values(charge_id)
      @metric_filter_values ||= {}
      @metric_filter_values[charge_id] ||= begin
        billable_metric_id = Charge.with_discarded.where(id: charge_id).pick(:billable_metric_id)
        BillableMetricFilter.where(billable_metric_id:).pluck(:key, :values).to_h
      end
    end

    def value_cells(values_list)
      tokens = values_list.compact.flat_map(&:to_a).group_by(&:first).transform_values do |pairs|
        (pairs.flat_map { |_key, allowed| Array(allowed) } - [ChargeFilterValue::ALL_FILTER_VALUES]).uniq + [OTHER_VALUE]
      end
      return [{}] if tokens.empty?
      return if tokens.values.map(&:size).reduce(:*) > MAX_VALUE_CELLS

      first, *rest = tokens.values
      first.product(*rest).map { |combination| tokens.keys.zip(combination).to_h }
    end

    def billers(cell, values_list)
      matching = values_list.each_index.select do |index|
        values_list[index]&.all? do |key, allowed|
          Array(allowed).include?(ChargeFilterValue::ALL_FILTER_VALUES) || Array(allowed).include?(cell[key])
        end
      end

      if matching.empty?
        values_list.each_index.select { |index| values_list[index].nil? }
      else
        precedence = ->(index) { filter_precedence(values_list[index]) }
        best = matching.map(&precedence).min
        matching.select { |index| precedence.call(index) == best }
      end
    end

    # Same order as ChargeFilter#precedence. An all-values filter left unexpanded, when its billable metric
    # filter is gone, ranks below any explicit list.
    def filter_precedence(values)
      size = values.sum do |_key, allowed|
        Array(allowed).include?(ChargeFilterValue::ALL_FILTER_VALUES) ? Float::INFINITY : Array(allowed).size
      end

      [-values.size, size]
    end

    def split(total, slots, claims = Array.new(slots.size, 1))
      return Array.new(slots.size, BigDecimal(0)) if total.zero? || slots.empty?

      gains = slots.zip(claims).map { |slot, claim| [slot_value(slot), BigDecimal(0)].max.to_r * claim }
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
