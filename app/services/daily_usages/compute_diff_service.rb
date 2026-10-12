# frozen_string_literal: true

module DailyUsages
  class ComputeDiffService < BaseService
    Result = BaseResult[:usage_diff]

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
    # keep their full period-to-date amounts as "diff" while the dropped filters' amounts are never
    # subtracted, so the filter diffs no longer add up to the charge diff.
    #
    # The amounts of the dropped filters are therefore deducted from the filters that were not matched
    # (where the re-bucketed usage landed), or from all current filters when every current filter was
    # matched (e.g. a filter was removed and its usage fell back into the default bucket).
    def apply_filters_diff(previous_parent, current_parent)
      current_filters = current_parent["filters"]
      current_values = current_filters.map { |fu| fu["values"] }.to_set
      allocation_weights = current_filters.map { |fu| cumulative_values(fu) }

      previous_filters_index = previous_parent["filters"].index_by { |fu| fu["values"] }
      unmatched_indexes = []

      current_filters.each_with_index do |current_filter, index|
        previous_filter = previous_filters_index[current_filter["values"]]
        unless previous_filter
          unmatched_indexes << index
          next
        end

        apply_diff(previous_filter, current_filter)
        apply_presentation_breakdowns_diff(previous_filter, current_filter)
      end

      dropped_filters = previous_parent["filters"].reject { |fu| current_values.include?(fu["values"]) }
      return if dropped_filters.empty?

      target_indexes = unmatched_indexes.presence || current_filters.each_index.to_a
      deduct_dropped_filters(
        dropped_filters,
        target_indexes.map { |index| current_filters[index] },
        target_indexes.map { |index| allocation_weights[index] }
      )
    end

    def deduct_dropped_filters(dropped_filters, targets, weights)
      return if targets.empty?

      dropped = dropped_filters.map { |fu| cumulative_values(fu) }
      shares = allocation_shares(weights)

      {
        "amount_cents" => dropped.sum { |values| values[:amount_cents] },
        "events_count" => dropped.sum { |values| values[:events_count] },
        "units" => dropped.sum(BigDecimal(0)) { |values| values[:units] }
      }.each do |field, total|
        allocate(total, shares).each_with_index do |amount, index|
          target = targets[index]

          target[field] = if field == "units"
            (BigDecimal(target[field]) - amount).to_s
          else
            target[field] - amount
          end
        end
      end
    end

    def cumulative_values(usage)
      {
        amount_cents: usage["amount_cents"],
        events_count: usage["events_count"],
        units: BigDecimal(usage["units"])
      }
    end

    # Allocation ratio of each target, based on its period-to-date amount, then units, then events count.
    def allocation_shares(weights)
      %i[amount_cents units events_count].each do |field|
        total = weights.sum { |values| values[field] }
        return weights.map { |values| Rational(values[field]) / total } if total.positive?
      end

      Array.new(weights.size, Rational(1, weights.size))
    end

    # Splits total according to shares. The last target takes the remainder, so the parts always add up
    # to the total. Integer totals (cents, events) are split into integers.
    def allocate(total, shares)
      integer = total.is_a?(Integer)
      parts = shares[0...-1].map do |share|
        integer ? (total * share).round : total * BigDecimal(share, 20)
      end

      parts << (total - parts.sum(integer ? 0 : BigDecimal(0)))
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
