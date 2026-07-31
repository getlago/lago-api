# frozen_string_literal: true

module BillableMetricFilters
  class CreateOrUpdateBatchService < BaseService
    Result = BaseResult[:filters]

    BATCH_SIZE = 1_000
    IMPACTED_PLAN_CODES_LIMIT = 10

    def initialize(billable_metric:, filters_params:, discard_impacted_charge_filters: false)
      @billable_metric = billable_metric
      @filters_params = filters_params
      @discard_impacted_charge_filters = discard_impacted_charge_filters
      @touched_charge_filter_ids = Set.new

      super
    end

    def call
      result.filters = []

      if filters_params.empty?
        discard_all_filters

        return result
      end

      return result.validation_failure!(errors: {values: ["value_is_mandatory"]}) if any_filter_params_values_blank?

      # NOTE: requires_new so the guard can undo its own discards; a nested block is not a savepoint.
      ActiveRecord::Base.transaction(requires_new: true) do
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

              discard_filter_values_in_batches(filter_values, new_values:)
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

        resolve_impacted_charge_filters!
      end

      return result if result.failure?

      BillableMetricFilters::RefreshDraftInvoicesJob.perform_after_commit(billable_metric.id)

      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :billable_metric, :filters_params, :discard_impacted_charge_filters, :touched_charge_filter_ids

    # NOTE: one per run. Bulk `update_all` skips PaperTrail, so this is the only trace, and the undo key.
    def discarded_at
      @discarded_at ||= Time.current
    end

    def any_filter_params_values_blank?
      filters_params.any? do |filter_param|
        filter_param[:values].blank?
      end
    end

    def discard_all_filters
      ActiveRecord::Base.transaction(requires_new: true) do
        billable_metric.filters.each { discard_filter(it) }

        resolve_impacted_charge_filters!
      end
    end

    def discard_filter(filter)
      discard_filter_values_in_batches(filter.filter_values)

      filter.discard!
    end

    def discard_filter_values_in_batches(filter_values, new_values: [])
      filter_values.unscope(:order).in_batches(of: BATCH_SIZE) do |filter_value_batch|
        values_to_trim, values_to_discard = filter_value_batch.partition { |fv| trimmable?(fv, new_values) }

        bulk_update_trimmed_filter_values(values_to_trim, new_values)
        discard_filter_values(values_to_discard)
      end
    end

    def trimmable?(filter_value, new_values)
      filter_value.values.intersect?(new_values)
    end

    def bulk_update_trimmed_filter_values(filter_values, new_values)
      return if filter_values.empty?

      filter_values.group_by { |fv| fv.values & new_values }.each do |result_values, group|
        ChargeFilterValue.where(id: group.map(&:id)).update_all( # rubocop:disable Rails/SkipsModelValidations
          values: result_values, updated_at: Time.current
        )
      end
    end

    def discard_filter_values(filter_values)
      return if filter_values.empty?

      touched_charge_filter_ids.merge(filter_values.map(&:charge_filter_id))

      ChargeFilterValue
        .where(id: filter_values.map(&:id))
        .update_all(deleted_at: discarded_at) # rubocop:disable Rails/SkipsModelValidations
    end

    def resolve_impacted_charge_filters!
      emptied_ids, collapsed_ids = partition_touched_charge_filters

      refuse_collapsed_charge_filters!(collapsed_ids) unless discard_impacted_charge_filters

      discarded_ids = emptied_ids + collapsed_ids
      return if discarded_ids.empty?

      discarded = ChargeFilters::BulkDiscardService.call!(charge_filter_ids: discarded_ids, discarded_at:)

      Rails.logger.info(
        "Discarded charge filters after a billable metric filter change: " \
        "billable_metric=#{billable_metric.id} discarded_at=#{discarded_at.iso8601(6)} " \
        "emptied=#{emptied_ids.size} collapsed=#{collapsed_ids.size} discarded=#{discarded.discarded_count}"
      )
    end

    def refuse_collapsed_charge_filters!(collapsed_ids)
      return if collapsed_ids.empty?

      result.validation_failure!(errors: collapsed_charge_filters_errors(collapsed_ids)).raise_if_error!
    end

    def partition_touched_charge_filters
      emptied_ids = []
      collapsed_ids = []

      touched_charge_filter_ids.each_slice(BATCH_SIZE) do |ids|
        kept_ids = ChargeFilter.where(id: ids, deleted_at: nil).unscope(:order).pluck(:id)
        next if kept_ids.empty?

        slice_emptied_ids = ChargeFilter
          .where(id: kept_ids, deleted_at: nil)
          .without_kept_values
          .unscope(:order)
          .pluck(:id)

        emptied_ids.concat(slice_emptied_ids)
        collapsed_ids.concat(kept_ids - slice_emptied_ids)
      end

      [emptied_ids, collapsed_ids]
    end

    def collapsed_charge_filters_errors(collapsed_ids)
      {
        filters: ["values_used_by_charge_filters"],
        impacted_charge_filters_count: [collapsed_ids.size.to_s],
        impacted_plan_codes: impacted_plan_codes(collapsed_ids)
      }
    end

    def impacted_plan_codes(collapsed_ids)
      ChargeFilter
        .where(id: collapsed_ids.first(BATCH_SIZE))
        .joins(charge: :plan)
        .unscope(:order)
        .distinct
        .limit(IMPACTED_PLAN_CODES_LIMIT)
        .pluck("plans.code")
    end
  end
end
