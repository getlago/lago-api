# frozen_string_literal: true

module DailyUsages
  # Recomputes the stored usage_diff of the daily usages written right after a charge's filters were
  # edited mid-period. Those rows were diffed while filters were matched on their values only, so the
  # filters created by the edit kept their whole period-to-date amounts as diff.
  #
  # A row is affected when, for a charge (or a grouped usage of a charge) present in both the row and
  # the previous row of the same billing period, the previous row holds filter values that the row no
  # longer has. Other rows are left untouched: DailyUsages::ComputeDiffService returns the same diff
  # for them as when they were written.
  class RecomputeDiffsService < BaseService
    Result = BaseResult[:daily_usages]

    def initialize(subscription:, from_date:, dry_run: false)
      @subscription = subscription
      @from_date = from_date
      @dry_run = dry_run

      super
    end

    def call
      result.daily_usages = affected_daily_usages

      unless dry_run
        result.daily_usages.each do |daily_usage|
          usage_diff = DailyUsages::ComputeDiffService.call!(daily_usage:).usage_diff
          daily_usage.update!(usage_diff:)
        end
      end

      result
    end

    private

    attr_reader :subscription, :from_date, :dry_run

    def affected_daily_usages
      # Rows of periods ending before from_date are not needed, but the row preceding from_date in the
      # same period is, as it is the reference of the first row in range.
      daily_usages = subscription.daily_usages
        .where("to_datetime >= ?", from_date)
        .order(:from_datetime, :usage_date)

      daily_usages.group_by { |du| [du.from_datetime, du.to_datetime] }.values.flat_map do |period_usages|
        period_usages.each_cons(2).filter_map do |previous, current|
          current if current.usage_date >= from_date && dropped_filters?(previous.usage, current.usage)
        end
      end
    end

    def dropped_filters?(previous_usage, current_usage)
      previous_index = filter_values_index(previous_usage)
      current_index = filter_values_index(current_usage)

      previous_index.any? do |key, previous_values|
        current_values = current_index[key]
        current_values && !previous_values.subset?(current_values)
      end
    end

    # Maps each charge, and each grouped usage of a charge, to the set of its filter values.
    def filter_values_index(usage)
      # usage defaults to the JSON string "{}" on rows that never got a snapshot
      return {} unless usage.is_a?(Hash)

      usage.fetch("charges_usage", []).each_with_object({}) do |charge_usage, index|
        charge_id = charge_usage.dig("charge", "lago_id")
        index[[charge_id]] = filter_values(charge_usage)

        charge_usage.fetch("grouped_usage", []).each do |grouped_usage|
          index[[charge_id, grouped_usage["grouped_by"]]] = filter_values(grouped_usage)
        end
      end
    end

    def filter_values(usage)
      usage.fetch("filters", []).map { |filter| filter["values"] }.to_set
    end
  end
end
