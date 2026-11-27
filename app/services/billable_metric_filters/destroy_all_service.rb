# frozen_string_literal: true

module BillableMetricFilters
  class DestroyAllService < BaseService
    Result = BaseResult[:billable_metric]

    def initialize(billable_metric)
      @billable_metric = billable_metric
      super
    end

    def call
      return result unless billable_metric
      return result unless billable_metric.discarded?

      deleted_at = Time.current

      billable_metric.filters.unscope(:order).find_each do |filter|
        # Read the values with discarded ones, so a re-run still finds the charge filters
        # after a previous run discarded their values.
        charge_filter_ids = ChargeFilterValue
          .with_discarded
          .where(billable_metric_filter_id: filter.id)
          .unscope(:order)
          .select(:charge_filter_id)

        # rubocop:disable Rails/SkipsModelValidations
        filter.filter_values.update_all(deleted_at:, updated_at: deleted_at)
        # The kept default scope leaves already discarded charge filters with their own deleted_at.
        ChargeFilter.where(id: charge_filter_ids).unscope(:order).update_all(deleted_at:, updated_at: deleted_at)
        # rubocop:enable Rails/SkipsModelValidations

        filter.discard!
      end

      result.billable_metric = billable_metric
      result
    end

    private

    attr_reader :billable_metric
  end
end
