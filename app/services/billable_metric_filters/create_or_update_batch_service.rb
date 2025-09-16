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
          filter = billable_metric.filters
            .create_with(organization_id: billable_metric.organization_id)
            .find_or_initialize_by(key: filter_param[:key])
          new_values = (filter_param[:values] || []).uniq

          if filter.persisted?
            deleted_values = filter.values - filter_param[:values]

            if deleted_values.present?
              filter_values = filter.filter_values
                .where(
                  deleted_values.map { "? = ANY(values)" }.join(" OR "),
                  *deleted_values
                )

              filter_values.each { |filter_value| discard_filter_value(filter_value, new_values:) }
            end
          end

          filter.values = new_values
          filter.save!

          result.filters << filter
        end

        # NOTE: discard all filters that were not created or updated
        billable_metric.filters.where.not(id: result.filters.map(&:id)).unscope(:order).find_each do
          discard_filter(it)
        end
      end

      refresh_draft_invoices

      result
    end

    private

    attr_reader :billable_metric, :filters_params

    def discard_all
      ActiveRecord::Base.transaction do
        billable_metric.filters.each { discard_filter(it) }
      end
    end

    def discard_filter(filter)
      filter.filter_values.each { discard_filter_value(it) }
      filter.discard!
    end

    def discard_filter_value(filter_value, new_values: [])
      deleted_values = filter_value.values - new_values

      if deleted_values.any?
        values = filter_value.values - deleted_values

        if values.any?
          filter_value.update!(values:)
          return
        end
      end

      filter_value.discard!
      return if filter_value.charge_filter.values.where.not(id: filter_value.id).exists?

      filter_value.charge_filter.discard! unless filter_value.charge_filter.discarded?
    end

    def refresh_draft_invoices
      draft_invoices = Invoice.draft.joins(plans: [:billable_metrics])
        .where(billable_metrics: {id: billable_metric.id})
        .distinct

      draft_invoices.update_all(ready_to_be_refreshed: true) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
