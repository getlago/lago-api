# frozen_string_literal: true

module DailyUsages
  class ComputeDiffService < BaseService
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

      diff["charges_usage"].each do |current_charge_usage|
        previous_charge_usage = previous_usage["charges_usage"].find { |cu| cu["charge"]["lago_id"] == current_charge_usage["charge"]["lago_id"] }
        next unless previous_charge_usage

        apply_diff(previous_charge_usage, current_charge_usage)

        current_charge_usage["filters"].each do |current_usage_filter|
          previous_usage_filter = previous_charge_usage["filters"].find { |fu| fu["values"] == current_usage_filter["values"] }
          next unless previous_usage_filter

          apply_diff(previous_usage_filter, current_usage_filter)
        end

        current_charge_usage["grouped_usage"].each do |current_grouped_usage|
          previous_grouped_usage = previous_charge_usage["grouped_usage"].find { |gu| gu["grouped_by"] == current_grouped_usage["grouped_by"] }
          next unless previous_grouped_usage

          apply_diff(previous_grouped_usage, current_grouped_usage)

          current_grouped_usage["filters"].each do |current_usage_filter|
            previous_usage_filter = previous_grouped_usage["filters"].find { |fu| fu["values"] == current_usage_filter["values"] }
            next unless previous_usage_filter

            apply_diff(previous_usage_filter, current_usage_filter)
          end
        end
      end

      diff["amount_cents"] = diff["charges_usage"].sum { |cu| cu["amount_cents"] }
      diff["taxes_amount_cents"] -= previous_common_taxes(diff, previous_usage)
      diff["total_amount_cents"] = diff["amount_cents"] + diff["taxes_amount_cents"]

      result.usage_diff = diff
      result
    end

    private

    attr_reader :daily_usage

    delegate :subscription, :usage_date, :from_datetime, :to_datetime, to: :daily_usage

    def previous_daily_usage
      @previous_daily_usage ||= subscription.daily_usages
        .where(from_datetime:, to_datetime:)
        .find_by(usage_date: usage_date - 1.day)
    end

    def previous_common_taxes(diff, previous_usage)
      return previous_usage["taxes_amount_cents"] unless previous_usage["amount_cents"].positive?

      common_charge_ids = diff["charges_usage"].map { |cu| cu["charge"]["lago_id"] }
      previous_common_amount = previous_usage["charges_usage"]
        .select { |cu| common_charge_ids.include?(cu["charge"]["lago_id"]) }
        .sum { |cu| cu["amount_cents"] }

      common_ratio = previous_common_amount.to_f / previous_usage["amount_cents"]
      (previous_usage["taxes_amount_cents"] * common_ratio).round
    end

    def apply_diff(previous_values, current_values)
      current_values["units"] = (BigDecimal(current_values["units"]) - BigDecimal(previous_values["units"])).to_s
      current_values["events_count"] -= previous_values["events_count"]
      current_values["amount_cents"] -= previous_values["amount_cents"]
    end
  end
end
