# frozen_string_literal: true

module BillableMetricFilters
  class CreateOrUpdateBatchService < BaseService
    def initialize(billable_metric:, filters_params:)
      @billable_metric = billable_metric
      @filters_params = filters_params

      super
    end

    def call
      result.filters = []

      if filters_params.empty?
        discard_all

        return result
      end

      ActiveRecord::Base.transaction do
        filters_params.each do |filter_param|
          filter = billable_metric.filters.find_or_initialize_by(key: filter_param[:key])

          if filter.persisted?
            deleted_values = filter.values - filter_param[:values]

            filter_values = filter.filter_values
              .where(billable_metric_filter_id: filter.id)
              .where(value: deleted_values)

            filter_values.each { discard_filter_value(_1) }
          end

          filter.values = (filter_param[:values] || []).uniq
          filter.save!

          result.filters << filter
        end

        # NOTE: discard all filters that were not created or updated
        billable_metric.filters.where.not(id: result.filters.map(&:id)).find_each do
          discard_filter(_1)
        end
      end

      result
    end

    private

    attr_reader :billable_metric, :filters_params

    def discard_all
      ActiveRecord::Base.transaction do
        billable_metric.filters.each { discard_filter(_1) }
      end
    end

    def discard_filter(filter)
      filter.filter_values.each { discard_filter_value(_1) }
      filter.discard!
    end

    def discard_filter_value(filter_value)
      filter_value.discard!
      return if filter_value.charge_filter.values.where.not(id: filter_value.id).exists?

      filter_value.charge_filter.discard!
    end
  end
end
