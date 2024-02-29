# frozen_string_literal: true

module ChargeFilters
  class CreateOrUpdateBatchService < BaseService
    def initialize(charge:, filters_params:)
      @charge = charge
      @filters_params = filters_params

      super
    end

    def call
      result.filters = []

      if filters_params.empty?
        remove_all

        return result
      end

      ActiveRecord::Base.transaction do
        filters_params.each do |filter_param|
          # NOTE: Find the filters matching the values
          filters = charge.filters.joins(values: :billable_metric_filter)
            .where(billable_metric_filters: { key: filter_param[:values].keys })
            .where(charge_filter_values: { value: filter_param[:values].values })

          # NOTE: since a filter could be a refinement of another one, we have to make sure
          #       that we are targeting the right one
          filter = filters.find { |f| f.values.count == filter_param[:values].count }
          filter ||= charge.filters.new

          filter.invoice_display_name = filter_param[:invoice_display_name]
          filter.properties = filter_param[:properties]

          # NOTE: Create or update the filter values
          filter_param[:values].each do |key, value|
            billable_metric_filter = charge.billable_metric.filters.find_by(key:)

            filter_value = filter.values.find_or_initialize_by(
              billable_metric_filter_id: billable_metric_filter&.id,
            )

            filter_value.value = value
          end

          filter.save!

          result.filters << filter
        end

        # NOTE: remove old filters that were not created or updated
        charge.filters.where.not(id: result.filters.map(&:id)).find_each do
          remove_filter(_1)
        end
      end

      result
    end

    private

    attr_reader :charge, :filters_params

    def remove_all
      ActiveRecord::Base.transaction do
        charge.filters.each { remove_filter(_1) }
      end
    end

    def remove_filter(filter)
      filter.values.each(&:discard!)
      filter.discard!
    end
  end
end
