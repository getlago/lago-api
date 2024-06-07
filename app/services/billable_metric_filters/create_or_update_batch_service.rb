# frozen_string_literal: true

module BillableMetricFilters
  class CreateOrUpdateBatchService < BaseService
    def initialize(billable_metric:, filters_params:, legacy_group_params: nil)
      @billable_metric = billable_metric
      @filters_params = filters_params
      @legacy_group_params = legacy_group_params

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
          new_values = (filter_param[:values] || []).uniq

          if filter.persisted?
            deleted_values = filter.values - filter_param[:values]

            if deleted_values.present?
              filter_values = filter.filter_values
                .where(
                  deleted_values.map { '? = ANY(values)' }.join(' OR '),
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
        billable_metric.filters.where.not(id: result.filters.map(&:id)).find_each do
          discard_filter(_1)
        end

        # NOTE: keep compatibility with old group structure by creating the default group properties (as filters)
        handle_charge_group_properties if legacy_group_params.present?
      end

      refresh_draft_invoices

      result
    end

    private

    attr_reader :billable_metric, :filters_params, :legacy_group_params

    def discard_all
      ActiveRecord::Base.transaction do
        billable_metric.filters.each { discard_filter(_1) }
      end
    end

    def discard_filter(filter)
      filter.filter_values.each { discard_filter_value(_1) }
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

      filter_value.charge_filter.discard!
    end

    def refresh_draft_invoices
      draft_invoices = Invoice.draft.joins(plans: [:billable_metrics])
        .where(billable_metrics: {id: billable_metric.id})
        .distinct

      draft_invoices.update_all(ready_to_be_refreshed: true) # rubocop:disable Rails/SkipsModelValidations
    end

    def handle_charge_group_properties
      billable_metric.groups.find_each do |group|
        next if group.children.any?

        group_values = group_values(group)

        charges_missing_group(group_values).each do |charge|
          filter = charge.filters.create!(
            invoice_display_name: nil,
            properties: charge[:properties]
          )

          group_values.each do |key, filter_values|
            billable_metric_filter = billable_metric.filters.find_by(key:)

            filter.values.create!(
              billable_metric_filter_id: billable_metric_filter&.id,
              values: filter_values
            )
          end
        end
      end
    end

    def group_values(group)
      values = {group.key => [group.value]}
      values[group.parent.key] = [group.parent.value] if group.parent
      values
    end

    def charges_missing_group(group_values)
      billable_metric.charges.all.select do |charge|
        filters = charge.filters.includes(values: :billable_metric_filter)

        filter = filters.find do |f|
          next unless f.to_h.sort == group_values.sort

          f.values.all? do |value|
            group_values[value.key].sort == value.values.sort
          end
        end

        filter.nil?
      end
    end
  end
end
